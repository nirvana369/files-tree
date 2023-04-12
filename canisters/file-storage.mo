import Types "types";

import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Hash "mo:base/Hash";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Buffer "mo:base/Buffer";
import Array "mo:base/Array";
import Nat8 "mo:base/Nat8";
import Debug "mo:base/Debug";
import Option "mo:base/Option";


shared ({caller}) actor class FileStorage() = this {

    // Bind the caller and the admin
    let _admin : Principal = caller;

    type File = Types.File;
    type FileChunk = Types.FileChunk;
    type FileState = Types.FileState;

    var IdGenFile = 0;

    let DATASTORE_CANISTER_CAPACITY : Nat = 2_000_000_000;

    // Size limit of each note is 1 MB.
    let FILE_DATA_SIZE = 1_000_000;

    var CHUNK_SIZE = 1_000_000; // 1 MB

    let _numberOfDataPerCanister : Nat = DATASTORE_CANISTER_CAPACITY / FILE_DATA_SIZE;

    var totalCanisterDataSize = 0;

    // stable var _stableDatastores : [(Nat, FileTree)] = [];
    // let _datastores = HashMap.fromIter<Nat, FileTree>(_stableDatastores.vals(), 10, Nat.equal, Hash.hash);
    let _datastores : HashMap.HashMap<Nat, File> = HashMap.HashMap<Nat, File>(10, Nat.equal, Hash.hash);

    let _chunkCache : HashMap.HashMap<Nat, [FileChunk]> = HashMap.HashMap<Nat, [FileChunk]>(10, Nat.equal, Hash.hash);

    // registry canister need call this func first before user upload file with file id
    // file required hash md5
    public shared ({caller}) func registerFile(file : File) : async File {
        // only filetree-registry (proxy) can call
        assert(caller == _admin);
        assert(file.fHash != null);

        // check storage available -> if not enough return fid = 0, file manager will create new storage canister
        IdGenFile := IdGenFile + 1;
        let ftmp : File = {
                    fId = ?IdGenFile;
                    fName = file.fName;
                    fHash = file.fHash;
                    fData = file.fData;
                    fState = #empty;
                    fOwner = file.fOwner;
                };
        _datastores.put(IdGenFile, ftmp);
        return ftmp;
    };

    public shared ({caller}) func removeChunksCache(fId : Nat) : async () {
        _chunkCache.delete(fId);
    };

    public shared ({caller}) func getChunksCache(fId : Nat) : async ?[FileChunk] {
        _chunkCache.get(fId);
    };

    /**
    *   Caching chunks and join chunks by file id & chunk id
    */
    private func _processChunk(fchunk : FileChunk) : FileState {
        let fc = _chunkCache.get(fchunk.fId);
        let arr = switch (fc) {
            case null {
                [];
            };
            case (?arr) {
                arr;
            };
        };

        let buf = Buffer.fromArray<FileChunk>(arr);
        buf.add(fchunk);
        _chunkCache.put(fchunk.fId, Buffer.toArray(buf));

        if (fchunk.fTotalChunk == buf.size()) {
            let map : HashMap.HashMap<Nat, [Nat8]> = HashMap.HashMap<Nat, [Nat8]>(1, Nat.equal, Hash.hash);
            var bufSize = 0;
            for (c in buf.vals()) {
                map.put(c.fChunkId, c.fData);
                bufSize += c.fData.size();
            };
            var i = 0;
            let ret = Buffer.fromArray<Nat8>([]);
            while (i < fchunk.fTotalChunk) {
                let barr = switch (map.get(i)) {
                    case null Debug.trap("Chunk not exist!");
                    case (?b) b;
                };
                ret.append(Buffer.fromArray<Nat8>(barr));
                i := i + 1;
            };
            // return
            _chunkCache.delete(fchunk.fId);
            let fileData = Buffer.toArray(ret);
            // check file hash & put
            totalCanisterDataSize := totalCanisterDataSize + fileData.size();
            let result = _putFileData(fchunk.fId, fileData);
            switch (result) {
                case null Debug.trap("File not found!!! Need registered");
                case (?id) {
                    return #ready;
                };
            }
        };
        return #empty;
    };
    
    public shared ({caller}) func streamUpFile(fchunk : FileChunk) : async Result.Result<FileState, Text> {
        let (fileOwner, fileRegistered) = _getPermission(caller, fchunk.fOwner, fchunk.fId);
        switch(fileRegistered) {
            case(null) { return #err "File is not registered!" };
            case(?file) {
                switch(fileOwner) {
                    case null { return #err "You're not file owner!" };
                    case (?owner) {
                        //
                        // if chunk == final -> check hash md5 -> return false if hash not same when register
                        // check file status -> only process when state = #empty or #update
                        if (file.fState == #empty) {
                            let state = _processChunk(fchunk);
                            return #ok state;
                        };
                        return #err "File has uploaded! Re-update file tree and change file status to #empty if you need re-upload file"
                    };
                };
            };
        };
    };

    private func _getPermission(caller : Principal, fileOwner : Principal, fileId : Nat) : (?Principal, ?File) {
        let storageFile = _datastores.get(fileId);
        let fOwner = switch(storageFile) {
            case(null) { null };
            case(?file) {
                let owner = if (caller == _admin) {
                    fileOwner;
                } else {
                    caller;
                };
                if (file.fOwner != owner) {
                     null;
                } else {
                    ?owner;
                };
            };
        };
        (fOwner, storageFile);
    };

    /**
    *   
    *   Chunk id default is 0
    */
    public shared ({caller}) func streamDownFile(paramFileOwner : Principal, id : Nat, chunkId : Nat) : async Result.Result<FileChunk, Text> {
        let (fileOwner, fileRegistered) = _getPermission(caller, paramFileOwner, id);
        switch(fileRegistered) {
            case(null) { return #err "File is not registered!" };
            case(?file) {
                switch(fileOwner) {
                    case null { return #err "You're not file owner!" };
                    case (?owner) {
                        switch (file.fState) {
                            case (#empty) return #err "File data is #empty";
                            case (#ready) {
                                let byteArr = Buffer.fromArray<Nat8>(Option.get<[Nat8]>(file.fData, []));
                                let totalChunk = if (byteArr.size() % CHUNK_SIZE != 0) { (byteArr.size() / CHUNK_SIZE) + 1 } else { byteArr.size() / CHUNK_SIZE };
                                if (chunkId < totalChunk) {
                                    let start = chunkId * CHUNK_SIZE;
                                    let length : Nat = if (start + CHUNK_SIZE <= byteArr.size()) CHUNK_SIZE else byteArr.size() - start;
                                    let chunk = Buffer.subBuffer(byteArr, start, length);
                                    return #ok {
                                        fId = id;
                                        fChunkId = chunkId;
                                        fTotalChunk = totalChunk;
                                        fData = Buffer.toArray(chunk);
                                        fOwner = owner;
                                    }
                                } else {
                                    // alway return chunk at index 0 if client dont know exactly chunkId
                                    // the next round client will know total chunk + chunkid client need get to join full file
                                    let length : Nat = if (CHUNK_SIZE > byteArr.size()) byteArr.size() else CHUNK_SIZE;
                                    let chunk = Buffer.subBuffer(byteArr, 0, length);
                                    return #ok {
                                        fId = 0;
                                        fChunkId = chunkId;
                                        fTotalChunk = totalChunk;
                                        fData = Buffer.toArray(chunk);
                                        fOwner = owner;
                                    }
                                }
                            };
                        };
                    };
                };
            };
        };
    };

    private func _putFileData(id : Nat, data : [Nat8]) : ?Nat {
        switch (_datastores.get(id)) {
            case(null) return null; // file not registered
            case(?file) { 
                // check hash md5 if hash not same when register -> error if has not equal

                // else if hash equal
                let ftmp = {
                    fId = file.fId;
                    fName = file.fName;
                    fHash = file.fHash;
                    fData = ?data;
                    fState = #ready;
                    fOwner = file.fOwner;
                };
                _datastores.put(id, ftmp);
            };
        };
        ?id;
    };

    public query ({caller}) func getFile(paramFileOwner : Principal, id : Nat) : async Result.Result<File, Text> {
        let (fileOwner, fileRegistered) = _getPermission(caller, paramFileOwner, id);
        switch (fileRegistered) {
            case null #err "File not exist";
            case (?f) #ok f;
        };
    };

    public shared ({caller}) func deleteFile(fOwner : Principal, id : Nat) : async Result.Result<Nat, Text> {
        let (fileOwner, fileRegistered) = _getPermission(caller, fOwner, id);
        switch(fileRegistered) {
            case(null) { return #err "File is not registered!" };
            case(?file) {
                switch(fileOwner) {
                    case null { return #err "You're not file owner!" };
                    case (?owner) {
                        _datastores.delete(id);
                        totalCanisterDataSize := totalCanisterDataSize - Option.get<[Nat8]>(file.fData, []).size();
                        #ok(id);
                    };
                };
            };
        };
    };

    public shared(msg) func getCanisterId() : async Principal {
        let canisterId = Principal.fromActor(this);
        return canisterId;
    };

    public func getCanisterMemoryAvailable() : async Nat {
        return DATASTORE_CANISTER_CAPACITY - totalCanisterDataSize;
    };

    public func getCanisterFilesAvailable() : async Nat {
        return (DATASTORE_CANISTER_CAPACITY - totalCanisterDataSize) / _numberOfDataPerCanister; // (DATASTORE_CANISTER_CAPACITY - current memory used) / number item per canister
    };

     // The work required before a canister upgrade begins.
    // system func preupgrade() {
    //     Debug.print("Starting pre-upgrade hook...");
    //     _stableDatastores := Iter.toArray(_datastores.entries());
    //     Debug.print("pre-upgrade finished.");
    // };

    // // The work required after a canister upgrade ends.
    // system func postupgrade() {
    //     Debug.print("Starting post-upgrade hook...");
    //     _stableDatastores := [];
    //     Debug.print("post-upgrade finished.");
    // };

    public shared ({caller}) func changeChunkSize(size : Nat) : async () {
        CHUNK_SIZE := size;
    };

    public query ({caller}) func whoami() : async Text {
        return Principal.toText(caller);
    };
};