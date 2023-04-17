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
import Time "mo:base/Time";
import Text "mo:base/Text";

 

shared ({caller}) actor class FileStorage() = this {

    // Bind the caller and the admin
    let _admin : Principal = caller;

    type File = Types.File;
    type FileChunk = Types.FileChunk;
    type FileState = Types.FileState;

    
    var IdGenChunk = 0;

    let DATASTORE_CANISTER_CAPACITY : Nat = 2_000_000_000;

    // Size limit of each note is 2 MB.
    let FILE_DATA_SIZE = 2_000_000;

    var CHUNK_SIZE = 1_000_000; // 1 MB

    let _numberOfDataPerCanister : Nat = DATASTORE_CANISTER_CAPACITY / FILE_DATA_SIZE;

    var totalCanisterDataSize = 0;

    var checkFileHash = false;

    // stable var _stableDatastores : [(Nat, FileTree)] = [];
    // let _datastores = HashMap.fromIter<Nat, FileTree>(_stableDatastores.vals(), 10, Nat.equal, Hash.hash);
    let _datastores : HashMap.HashMap<Nat, File> = HashMap.HashMap<Nat, File>(10, Nat.equal, Hash.hash);

    let _chunkCache : HashMap.HashMap<Nat, FileChunk> = HashMap.HashMap<Nat, FileChunk>(10, Nat.equal, Hash.hash);

    // EVENT BUS SECTION - Cross canister notify & handle event

    private func _updateFileChunk(fileId : Nat, chunkInfo: Types.ChunkInfo) : async () {
        switch (_datastores.get(fileId)) {
            case(null) {}; // file not registered
            case(?file) { 
                // check hash md5 if hash not same when register -> error if has not equal
                var buf = Buffer.fromArray<Types.ChunkInfo>(file.chunks);
                buf.add(chunkInfo);
                // else if hash equal
                var state : Types.FileState = #empty;
                if (buf.size() == file.totalChunk) {
                    let map = HashMap.HashMap<Nat, Types.ChunkInfo>(0, Nat.equal, Hash.hash);
                    // group all chunkid by canister id
                    for (chunk in buf.vals()) {
                        switch(map.get(chunk.chunkOrderId)) {
                                case(?dupplicateChunk) { 
                                    // process delete dupplicate chunk Id
                                    let canister : Types.FileStorage = actor (chunk.canisterId);
                                    await canister.deleteChunk(chunk.canisterChunkId);
                                };
                                case(null) { 
                                    map.put(chunk.chunkOrderId, chunk);
                                };
                            };
                    };
                    
                    buf.clear();
                    buf := Buffer.fromIter<Types.ChunkInfo>(map.vals());

                    if (map.size() == file.totalChunk) { // if collected enough chunks
                        if (checkFileHash) {
                            // join file - hash - compare hash
                        };
                        state := #ready;
                        // notify 
                        ignore notify(Principal.toText(_admin), (#UpdateFileState (file.rootId, file.id)));
                    };
                    
                };
                let ftmp = {
                        rootId = file.rootId;
                        id = file.id;
                        name = file.name;
                        hash = file.hash;
                        chunks = Buffer.toArray(buf);
                        totalChunk = file.totalChunk;
                        state = state;
                        owner = caller;
                        size = file.size;
                        lastTimeUpdate = Time.now();
                };
                _datastores.put(fileId, ftmp);
            };
        };
    };

    public shared ({caller}) func eventHandler(event : Types.Event) : async () {
        switch(event) {
            case(#StreamUpChunk (fileId, chunkInfo)) { 
                await _updateFileChunk(fileId, chunkInfo);
            };
            case (_) {
                // not process if receive
                // counter number call
            };
        };
    };

    private func notify(canisterId : Text, e : Types.Event) : async () {
        let registry : Types.EventBus = actor (canisterId);
        ignore registry.eventHandler(e);
    };
    // FILE STORAGE SECTION : CRUD function

    public shared ({caller}) func putFile(file : File) : async File {
        // only filetree-registry (proxy) can call
        assert(caller == _admin);
        // check storage available -> if not enough return fid = 0, file manager will create new storage canister
        // if (file.size > _remainMemory()) {
        //     Debug.trap("You need add some cycle to canister registry: " # Principal.toText(_admin));
        // };
        _datastores.put(file.id, file);
        return file;
    };

    public query ({caller}) func readFile(id : Nat) : async ?File {
        assert(caller == _admin);
        let storageFile = _datastores.get(id);
        switch (storageFile) {
            case null null;
            case (f) f;
        };
    };

    public shared ({caller}) func deleteFile(id : Nat) : async Result.Result<Nat, Text> {
        assert(caller == _admin);
        // delete all chunk
        switch (_datastores.get(id)) {
            case null {};
            case (?file) {
                for (chunk in file.chunks.vals()) {
                    let canister : Types.FileStorage = actor (chunk.canisterId);
                    await canister.deleteChunk(chunk.canisterChunkId);
                };
            };
        };
        _datastores.delete(id);
        #ok id;
    };

    // CHUNK SECTION

    public shared ({caller}) func deleteChunk(chunkId : Nat) : async () {
        _chunkCache.delete(chunkId);
    };
    
    public shared ({caller}) func streamUp(fileCanisterId : Text, fchunk : FileChunk) : async ?Nat {
        // let (fileOwner, fileRegistered) = _getPermission(caller, fchunk.owner, fchunk.fileId);
        assert(caller == _admin);

        // does need verify file first ?
        IdGenChunk := IdGenChunk + 1;

        _chunkCache.put(IdGenChunk, fchunk);

        let chunkInfo : Types.ChunkInfo = {
            canisterChunkId = IdGenChunk;
            canisterId = Principal.toText(Principal.fromActor(this));
            chunkOrderId = fchunk.chunkOrderId;
        };

        ignore notify(fileCanisterId, (#StreamUpChunk (fchunk.fileId, chunkInfo)));

        (?IdGenChunk);
    };

    /**
    *   
    *   Chunk id default is 0
    */
    public shared ({caller}) func streamDown(chunkId : Nat) : async ?FileChunk {
        assert(caller == _admin);

        switch (_chunkCache.get(chunkId)) {
            case null null;
            case (chunk) chunk;
        }
    };

    public shared(msg) func getCanisterId() : async Principal {
        let canisterId = Principal.fromActor(this);
        return canisterId;
    };

    private func _remainMemory() : Nat {
        return DATASTORE_CANISTER_CAPACITY - totalCanisterDataSize;
    };

    public func getCanisterMemoryAvailable() : async Nat {
        _remainMemory();
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