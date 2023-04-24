import Types "types";
import RBAC "roles";
import Profiler "profiler";

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
import Iter "mo:base/Iter";
 

shared ({caller}) actor class FileStorage(_admin : [Principal], _storage : [Principal]) = this {

    let profiler = Profiler.Profiler("FileStorage");

    let rm : RBAC.Role = RBAC.init(caller, _admin, _storage);

    stable var IdGenChunk = 0;

    let DATASTORE_CANISTER_CAPACITY : Nat = 2_000_000_000;

    var CHUNK_SIZE = 2_000_000; // 2 MB

    let _numberOfDataPerCanister : Nat = DATASTORE_CANISTER_CAPACITY / CHUNK_SIZE;

    stable var totalCanisterDataSize = 0;

    var checkFileHash = false;

    stable var _stableDatastores : [(Nat, Types.File)] = [];
    stable var _stableChunks : [(Nat, Types.FileChunk)] = [];

    let _datastores : HashMap.HashMap<Nat, Types.File> = HashMap.fromIter<Nat, Types.File>(_stableDatastores.vals(), 10, Nat.equal, Hash.hash);

    let _chunkData : HashMap.HashMap<Nat, Types.FileChunk> = HashMap.fromIter<Nat, Types.FileChunk>(_stableChunks.vals(), 10, Nat.equal, Hash.hash);

    // EVENT BUS SECTION - Cross canister notify & handle event (process oneway message)

    private func _updateFileChunk(fileId : Nat, chunkInfo: Types.ChunkInfo) : async () {
        let p = profiler.push("_updateFileChunk");
        switch (_datastores.get(fileId)) {
            case(null) {}; // file not registered
            case(?file) { 
                // check hash md5 if hash not same when register -> error if has not equal
                var buf = Buffer.fromArray<Types.ChunkInfo>(file.chunks);
                buf.add(chunkInfo);
                // else if hash equal
                var state : Types.FileState = #empty;
                
                let map = HashMap.HashMap<Nat, Types.ChunkInfo>(0, Nat.equal, Hash.hash);
                // group all chunkid by canister id
                for (chunk in buf.vals()) {
                    switch(map.get(chunk.chunkOrderId)) {
                            case(?dupplicateChunk) { 
                                // process delete dupplicate chunk Id
                                let canister : Types.FileStorage = actor (chunk.canisterId);
                                ignore canister.deleteChunk(file.id, chunk.canisterChunkId);
                            };
                            case(null) { 
                                map.put(chunk.chunkOrderId, chunk);
                            };
                        };
                };
                
                buf.clear();
                buf := Buffer.fromIter<Types.ChunkInfo>(map.vals());

                if (buf.size() == file.totalChunk) { // if collected enough chunks
                    if (checkFileHash) {
                        // join file - hash - compare hash if needed
                    };
                    state := #ready;
                    // notify to file manager
                    await rm.asynIterAdmins(func (admin : Principal) : async() {
                        ignore notify(Principal.toText(admin), (#UpdateFileState (file.rootId, file.id)));
                    });
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
        profiler.pop(p);
    };

    public shared ({caller}) func eventHandler(event : Types.Event) : async () {
        let p = profiler.push("eventHandler");
        if (not _validCaller(caller)) {
            return;
        };
        switch(event) {
            case(#StreamUpChunk (fileId, chunkInfo)) { 
                await _updateFileChunk(fileId, chunkInfo);
            };
            case(#SyncRole(roles : [(Principal, Types.Roles)])) {
                for (r in roles.vals()) {
                    switch(r.1) {
                        case (#admin) rm.addAdmin(r.0);
                        case (#superadmin) rm.setSuperAdmin(r.0);
                        case (#storage) rm.addStorage(r.0);
                        case (_) {};
                    };
                };
            };
            case (_) {
                // not process if receive
                // monitor number wrong call
            };
        };
        profiler.pop(p);
    };

    private func notify(canisterId : Text, e : Types.Event) : async () {
        let p = profiler.push("notify." # canisterId);

        let registry : Types.EventBus = actor (canisterId);
        ignore registry.eventHandler(e);

        profiler.pop(p);
    };
    // FILE STORAGE SECTION : CRUD function

    public shared ({caller}) func putFile(file : Types.File) : async ?Types.File {
        if (not _validCaller(caller)) {
            return null;
        };
        let p = profiler.push("putFile");
        // check storage available -> if not enough return fid = 0, file manager will create new storage canister
        // if (file.size > _remainMemory()) {
        //     Debug.trap("You need add some cycle to canister registry: " # Principal.toText(_admin));
        // };
        _datastores.put(file.id, file);
        totalCanisterDataSize := totalCanisterDataSize + 1_000; // 1 kB metadata

        profiler.pop(p);

        return ?file;
    };

    public query ({caller}) func readFile(id : Nat) : async ?Types.File {
        let p = profiler.push("readFile");
        let storageFile = _datastores.get(id);
        
        switch (storageFile) {
            case null null;
            case (?f) {
                if (not _validCaller(caller) and caller != f.owner) {
                    return null;
                };
                profiler.pop(p);
                ?f;
            };
        };
    };

    public shared ({caller}) func deleteFile(id : Nat) : async Result.Result<Nat, Text> {
        // delete all chunk
        let p = profiler.push("deleteFile");
                    
        switch (_datastores.get(id)) {
            case null { return #err "File not exist!"};
            case (?file) {
                if (not _validCaller(caller) and caller != file.owner) {
                    return #err "You're not file owner";
                };
                for (chunk in file.chunks.vals()) {
                    let canister : Types.FileStorage = actor (chunk.canisterId);
                    await canister.deleteChunk(file.id, chunk.canisterChunkId);
                };
            };
        };
        _datastores.delete(id);
        if (totalCanisterDataSize >= 1000) {
            totalCanisterDataSize := totalCanisterDataSize - 1_000; // 1 kB metadata
        };
        profiler.pop(p);

        #ok id;
    };

    // CHUNK SECTION

    public shared ({caller}) func deleteChunk(fileId : Nat, chunkId : Nat) : async () {
        // only admin/ super user/ storages can call this func
        let p = profiler.push("deleteChunk");
        if (not _validCaller(caller)) {
            return;
        };
        switch (_chunkData.get(chunkId)) {
            case null ();
            case (?chunk) {
                if (chunk.fileId == fileId) {
                    if (totalCanisterDataSize >= chunk.data.size()) {
                        totalCanisterDataSize := totalCanisterDataSize - chunk.data.size();
                    };
                    _chunkData.delete(chunkId);
                };
            };
        };
        profiler.pop(p);
    };
    
    public shared ({caller}) func streamUp(fileCanisterId : Text, chunk : Types.FileChunk) : async ?Nat {

        let p = profiler.push("streamUp");

        if (not _validCaller(caller)) {
            return null;
        };
        IdGenChunk := IdGenChunk + 1;

        _chunkData.put(IdGenChunk, chunk);

        let chunkInfo : Types.ChunkInfo = {
            canisterChunkId = IdGenChunk;
            canisterId = Principal.toText(Principal.fromActor(this));
            chunkOrderId = chunk.chunkOrderId;
        };

        if (Principal.fromText(fileCanisterId) != Principal.fromActor(this)) {
            ignore notify(fileCanisterId, (#StreamUpChunk (chunk.fileId, chunkInfo)));
        } else {
            await _updateFileChunk(chunk.fileId, chunkInfo);
        };
        

        totalCanisterDataSize := totalCanisterDataSize + chunk.data.size();

        profiler.pop(p);

        (?IdGenChunk);
    };

    
    public query ({caller}) func streamDown(chunkId : Nat) : async ?Types.FileChunk {
        let p = profiler.push("streamDown");

        if (not _validCaller(caller)) {
            Debug.trap("Permission invalid");
        };

        let ret = switch (_chunkData.get(chunkId)) {
            case null null;
            case (chunk) chunk;
        };
        profiler.pop(p);

        ret;
    };

    public shared(msg) func getCanisterId() : async Principal {
        let canisterId = Principal.fromActor(this);
        return canisterId;
    };

    public query func getRoles() : async [(Principal, Types.Roles)] {
        rm.getRoles();
    };

    private func _remainMemory() : Nat {
        return DATASTORE_CANISTER_CAPACITY - totalCanisterDataSize;
    };

    public func getCanisterMemoryAvailable() : async Nat {
        _remainMemory();
    };

    public func getCanisterFilesAvailable() : async Nat {
        return (DATASTORE_CANISTER_CAPACITY - totalCanisterDataSize) / _numberOfDataPerCanister;
    };

    //  The work required before a canister upgrade begins.
    system func preupgrade() {
        Debug.print("Starting pre-upgrade hook...");
        _stableDatastores := Iter.toArray(_datastores.entries());
        _stableChunks := Iter.toArray(_chunkData.entries());
        Debug.print("pre-upgrade finished.");
    };

    // The work required after a canister upgrade ends.
    system func postupgrade() {
        Debug.print("Starting post-upgrade hook...");
        _stableDatastores := [];
        _stableChunks := [];
        Debug.print("post-upgrade finished.");
    };

    public shared ({caller}) func changeChunkSize(size : Nat) : async () {
        CHUNK_SIZE := size;
    };

    public query ({caller}) func whoami() : async Text {
        return Principal.toText(caller);
    };

    private func _validCaller(caller : Principal) : Bool {
        switch (rm.verify(caller)) {
            case (null or ?#anonymous or ?#user) return false;
            case (_) return true;
        };
    };

    public func getProfiler() : async [Profiler.ProfileResult] {
        profiler.get();
    }
};