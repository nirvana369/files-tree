import FileStorage "file-storage";
import ICType "IC";
import Types "types";

import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import List "mo:base/List";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Hash "mo:base/Hash";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Option "mo:base/Option";




shared ({caller}) actor class FileRegistry() = this {
    // Bind the caller and the admin
    let _admin : Principal = caller;

    let IC : ICType.Self = actor "aaaaa-aa";

    // The IC management canister.
    // See https://smartcontracts.org/docs/interface-spec/index.html#ic-management-canister
    // let IC : ICType.Self = actor "aaaaa-aa";

    // Currently, a single canister smart contract is limited to 4 GB of storage due to WebAssembly limitations.
    // To ensure that our datastore canister does not exceed this limit, we restrict memory usage to at most 2 GB because 
    // up to 2x memory may be needed for data serialization during canister upgrades. 
    let DATASTORE_CANISTER_CAPACITY : Nat = 2_000_000_000;

    // Size limit of each note is 1 MB.
    let FILE_DATA_SIZE = 1_000_000;

    let _numberOfDataPerCanister : Nat = DATASTORE_CANISTER_CAPACITY / FILE_DATA_SIZE;

    var IdGen : Nat = 0;

    stable var UserIdGen : Nat = 0;

    stable var _currentDatastoreCanisterId : ?Principal = null;
    stable var _stableDatastoreCanisterIds : [Principal] = [];
    stable var _stableFileTreeRegistry : [(Principal, [Nat])] = [];
    stable var _stableFileTreeStorage : [(Nat, Types.FileTree)] = [];
    stable var _stableUserIdRegistry : [(Principal, Nat)] = [];

    var _dataStoreCanister : ?Types.FileStorage = null;
    var _datastoreCanisterIds = List.fromArray(_stableDatastoreCanisterIds);

    let _fileTreeStorage : HashMap.HashMap<Nat, Types.FileTree> = HashMap.fromIter<Nat, Types.FileTree>(_stableFileTreeStorage.vals(), 10, Nat.equal, Hash.hash);
    let _fileTreeRegistry : HashMap.HashMap<Principal, [Nat]> = HashMap.fromIter<Principal, [Nat]>(_stableFileTreeRegistry.vals(), 10, Principal.equal, Principal.hash);

    public shared ({caller}) func verifyFileTree(fileTree : Types.FileTree) : async Types.FileTree {
        // get list file tree of caller

        // loop and recursive compare file name && file hash && 

        fileTree;
    };

    public shared ({caller}) func createFileTree(fileTree : Types.FileTree) : async Result.Result<Types.FileTree, Text> {
        // read file tree 
        let mutFileTree = _convert2MutableFileTree(fileTree);
        // call to canister files storage to register file id
        await _recursiveRegisterFileTree(caller, mutFileTree);
        // update FileTree -> file will have canister id + id
        IdGen := IdGen + 1;
        mutFileTree.fId := ?IdGen;
        let imutableFileTree = _convert2FileTree(mutFileTree);
        // return result for client -> client call canister file storage by canister id + id file to upload direct
        _putRegistry(caller, IdGen);
        _putFileTree(IdGen, imutableFileTree);

        #ok(imutableFileTree);
    };

    public shared ({caller}) func updateFileTree(fileTree : Types.FileTree) : async Result.Result<Types.FileTree, Text> {
        // read file tree 
        let fTreeId = switch (fileTree.fId) {
            case null return #err "File tree not registered!";
            case (?id) {
                id;
            };
        };
        let mutFileTree = _convert2MutableFileTree(fileTree);
        // call to canister files storage to register file id
        await _recursiveUpdateFileTree(caller, mutFileTree);
        // update FileTree -> file will have canister id + id
        let imutableFileTree = _convert2FileTree(mutFileTree);
        // return result for client -> client call canister file storage by canister id + id file to upload direct
        _putFileTree(fTreeId, imutableFileTree);

        #ok(imutableFileTree);
    };

    public query ({caller}) func getFileTree(id : Nat) : async Result.Result<Types.FileTree, Text> {
        switch (_getFileTree(id)) {
            case null #err "File tree are not exist!";
            case (?fTree) #ok fTree;
        };
    };

    public query ({caller}) func getListFileTree() : async Result.Result<[Types.FileTree], Text> {
        switch (_fileTreeRegistry.get(caller)) {
            case null {
                #err "Your file tree is empty!";
            };
            case (?arr) {
                let fTree = Array.mapFilter<Nat, Types.FileTree>(arr, func(id) {
                    _getFileTree(id);
                });
                #ok fTree;
            };
        };
    };

    public query ({caller}) func getStorageCanisters() : async [Principal] {
        List.toArray(_datastoreCanisterIds);
    };

    // inter canister func

    // public shared ({caller}) func putFile(canisterId : Text, id : Nat, data : [Nat8]) : async Result.Result<Nat, Text> {
    //     let canister : Types.FileStorage = actor(canisterId);
    //     await canister.proxyPutFile(caller, id, data);
    // };

    // public shared ({caller}) func getFile(canisterId : Text, id : Nat) : async Result.Result<Types.File, Text> {
    //     let canister : Types.FileStorage = actor(canisterId);
    //     await canister.proxyGetFile(caller, id);
    // };

    public shared ({caller}) func deleteFileTree(id : Nat) : async Result.Result<Nat, Text> {
        switch (_getFileTree(id)) {
            case null #err "File tree are not exist!";
            case (?fTree) {
                await _recursiveDeleteFileTree(caller, fTree);
                _fileTreeStorage.delete(id);
                #ok id;
            };
        };
    };

    public shared ({caller}) func removeChunksCache(canisterId : Text, fId : Nat) : async () {
        let canister : Types.FileStorage = actor(canisterId);
        await canister.removeChunksCache(fId);
    };

    public shared ({caller}) func streamUpFile(fileTreeId : Nat, canisterId : Text, fchunk : Types.FileChunk) : async Result.Result<Types.FileState, Text> {
        let canister : Types.FileStorage = actor(canisterId);
        let chunk = {
                        fId = fchunk.fId;
                        fChunkId = fchunk.fChunkId;
                        fTotalChunk = fchunk.fTotalChunk;
                        fData = fchunk.fData;
                        fOwner = caller;
                    };
        let ret = await canister.streamUpFile(chunk);
        switch (ret) {
            case (#ok(state)) {
                if (state == #ready) {
                    _updateFileState(fileTreeId, fchunk.fId, state);
                };
            };
            case (_) {};
        };
        return ret;
    };

    private func _updateFileState(fId : Nat, fileId : Nat, state : Types.FileState) {
        let fileTree = _getFileTree(fId);
        switch (fileTree) {
            case null {};
            case (?ft) {
                let mutFileTree = _convert2MutableFileTree(ft);
                // call to canister files storage to register file id
                let ret = _recursiveUpdateFileState(mutFileTree, fileId, state);
                // update FileTree -> file will have canister id + id
                let imutableFileTree = _convert2FileTree(mutFileTree);
                // return result for client -> client call canister file storage by canister id + id file to upload direct
                _putFileTree(fId, imutableFileTree);
            };
        };
    };

    private func _recursiveUpdateFileState(fileTree : Types.MutableFileTree, fileId : Nat, state : Types.FileState) : Bool {
        switch (fileTree.fType) {
            case (#file) {
                switch (fileTree.fId) {
                    case null {return false;};
                    case (?id) {
                        if (id == fileId) {
                            fileTree.fState := state;
                            return true;
                        };
                        return false;
                    }
                };
            };
            case (#directory) {
                switch (fileTree.children) {
                    case null {
                        return false;
                        // do nothing
                    };
                    case (?childs) {
                        for (child in childs.vals()) {
                            let ret = _recursiveUpdateFileState(child, fileId, state);
                            if (ret == true) return true;
                        };
                        return false;
                    };
                };
            };
        };
    };

    public shared ({caller}) func streamDownFile(canisterId : Text, id : Nat, chunkId : Nat) : async Result.Result<Types.FileChunk,Text> {
        let canister : Types.FileStorage = actor(canisterId);
        await canister.streamDownFile(caller, id, chunkId);
    };

    // internal func

    private func checkStorageAvailable() : async ?Principal {
        for (canisterId in List.toIter<Principal>(_datastoreCanisterIds)) {
            let canister : Types.FileStorage = actor(Principal.toText(canisterId));
            let filesAvailable = await canister.getCanisterFilesAvailable();
            let memAvailable = await canister.getCanisterMemoryAvailable();
            if (filesAvailable > 100 and memAvailable > 200_000_000) {
                return ?canisterId;
            };
        };
        switch (await _generateFileStorage()) {
            case (#err(_)) null;
            case (#ok(canisterId)) ?canisterId;
        };
    };

    private func _generateFileStorage() : async Result.Result<Principal,Text>{
        try {
            Cycles.add(4_000_000_000_000);
            let fileStorageCanister = await FileStorage.FileStorage();
            let canisterId = Principal.fromActor(fileStorageCanister);

            _currentDatastoreCanisterId := ?canisterId;
            _dataStoreCanister := ?fileStorageCanister;
            _datastoreCanisterIds := List.push(canisterId, _datastoreCanisterIds);

            let settings: ICType.CanisterSettings = { 
                controllers = [_admin, Principal.fromActor(this)];
            };
            let params: ICType.UpdateSettings = {
                canister_id = canisterId;
                settings = settings;
            };
            await IC.update_settings(params);

            #ok (canisterId);
        } catch (e) {
            #err "An error occurred in generating a datastore canister.";
        }
    };

    private func _recursiveRegisterFileTree(owner : Principal, fileTree : Types.MutableFileTree) : async () {
        switch (fileTree.fType) {
            case (#file) {
                let file : Types.File = {
                    fId = fileTree.fId;
                    fName = fileTree.fName;
                    fHash = fileTree.fHash;
                    fData = null;
                    fState = #empty;
                    fOwner = owner;
                };

                // check fid == null -> state empty else state != null -> not register file -> return current file uploaded
                    let storageCanisterId = switch (_currentDatastoreCanisterId) {
                                                case null {
                                                    // find in list ?
                                                    // create new ?
                                                    let ret = await checkStorageAvailable();
                                                    let canister = switch (ret) {
                                                        case (?id) {
                                                            id;
                                                        };
                                                        case (null) {
                                                            Debug.trap("Can't create canister storage! May be Cycles are not enough");
                                                        };
                                                    };
                                                    canister;
                                                };
                                                case (?id) {
                                                id;
                                                };
                                            };
                    let storageCanister : Types.FileStorage = actor(Principal.toText(storageCanisterId));
                    let registeredFile = await storageCanister.registerFile(file);
                    fileTree.fId := registeredFile.fId;
                    fileTree.fCanister := ?Principal.toText(storageCanisterId);
            };
            case (#directory) {
                switch (fileTree.children) {
                    case null {
                        // do nothing
                    };
                    case (?childs) {
                        for (child in childs.vals()) {
                            await _recursiveRegisterFileTree(owner, child);
                        };
                    };
                };
            };
        };
    };

    private func _registerFile(file : Types.File) : async (Principal, Types.File) {
        let storageCanisterId = switch (_currentDatastoreCanisterId) {
                                                case null {
                                                    // find in list ?
                                                    // create new ?
                                                    let ret = await checkStorageAvailable();
                                                    let canister = switch (ret) {
                                                        case (?id) {
                                                            id;
                                                        };
                                                        case (null) {
                                                            Debug.trap("Can't create canister storage! May be Cycles are not enough");
                                                        };
                                                    };
                                                    canister;
                                                };
                                                case (?id) {
                                                id;
                                                };
                                            };
        let storageCanister : Types.FileStorage = actor(Principal.toText(storageCanisterId));
        let registeredFile = await storageCanister.registerFile(file);
        (storageCanisterId, registeredFile);
    };

    private func _recursiveUpdateFileTree(owner : Principal, fileTree : Types.MutableFileTree) : async () {
        switch (fileTree.fType) {
            case (#file) {
                // check fid == null -> register file else return current file uploaded
                switch(fileTree.fId) {
                    case (null) {  
                        let file : Types.File = {
                            fId = fileTree.fId;
                            fName = fileTree.fName;
                            fHash = fileTree.fHash;
                            fData = null;
                            fState = #empty;
                            fOwner = owner;
                        };
                        let (storageCanisterId, registeredFile) = await _registerFile(file);
                        fileTree.fId := registeredFile.fId;
                        fileTree.fCanister := ?Principal.toText(storageCanisterId);
                        fileTree.fState := registeredFile.fState;
                    };
                    case (?fileId) { 
                        // verify file
                        switch (fileTree.fCanister) {
                            case null {
                                // has file id but canister not exist ??
                            };
                            case (?canisterId) {
                                let storageCanister : Types.FileStorage = actor(canisterId);
                                let ret = await storageCanister.getFile(owner, fileId);
                                switch (ret) {
                                    case (#ok(f)) {
                                        fileTree.fState := f.fState;
                                    };
                                    case (#err(e)) {
                                        // file not exist -> wrong file id 
                                    };
                                };
                            };
                        };
                    };
                };
            };
            case (#directory) {
                switch (fileTree.children) {
                    case null {
                        // do nothing
                    };
                    case (?childs) {
                        for (child in childs.vals()) {
                            await _recursiveUpdateFileTree(owner, child);
                        };
                    };
                };
            };
        };
    };

    private func _recursiveDeleteFileTree(owner : Principal, fileTree : Types.FileTree) : async () {
        switch (fileTree.fType) {
            case (#file) {
                // check fid == null -> register file else return current file uploaded
                switch(fileTree.fId) {
                    case (null) { };
                    case (?fileId) { 
                        // verify file
                        switch (fileTree.fCanister) {
                            case null {
                                // has file id but canister not exist ??
                            };
                            case (?canisterId) {
                                let storageCanister : Types.FileStorage = actor(canisterId);
                                let ret = await storageCanister.deleteFile(owner, fileId);
                            };
                        };
                    };
                };
            };
            case (#directory) {
                switch (fileTree.children) {
                    case null {
                        // do nothing
                    };
                    case (?childs) {
                        for (child in childs.vals()) {
                            await _recursiveDeleteFileTree(owner, child);
                        };
                    };
                };
            };
        };
    };
    
    private func _putRegistry(owner : Principal, fTreeId : Nat) {
        switch (_fileTreeRegistry.get(owner)) {
            case null {
                _fileTreeRegistry.put(owner, [fTreeId]);
            };
            case (?arr) {
                let x = Buffer.fromArray<Nat>(arr);
                x.add(fTreeId);
                _fileTreeRegistry.put(owner, Buffer.toArray<Nat>(x));
            };
        };
    };

    private func _putFileTree(fTreeId : Nat, fTree : Types.FileTree) {
        _fileTreeStorage.put(fTreeId, fTree);
    };

    private func _getFileTree(id : Nat) : ?Types.FileTree {
        _fileTreeStorage.get(id);
    };

    private func _convert2MutableFileTree(fileTree : Types.FileTree) : Types.MutableFileTree {
        let c = switch (fileTree.children) {
            case null null;
            case (?childs) {
                ?Array.map<Types.FileTree, Types.MutableFileTree>(childs, func (c) {
                    _convert2MutableFileTree(c);
                });
            };
        };
        let mut : Types.MutableFileTree = {
            var fId = fileTree.fId;
            var fType = fileTree.fType;
            var fName = fileTree.fName;
            var fCanister = fileTree.fCanister;
            var fHash = fileTree.fHash;
            var fState = fileTree.fState;
            var children = c;
        };
        return mut;
    };

    private func _convert2FileTree(fileTree : Types.MutableFileTree) : Types.FileTree {
        let c = switch (fileTree.children) {
            case null null;
            case (?childs) {
                ?Array.map<Types.MutableFileTree, Types.FileTree>(childs, func (c) {
                    _convert2FileTree(c);
                });
            };
        };
        let mut : Types.FileTree = {
            fId = fileTree.fId;
            fType = fileTree.fType;
            fName = fileTree.fName;
            fCanister = fileTree.fCanister;
            fHash = fileTree.fHash;
            fState = fileTree.fState;
            children = c;
        };
        return mut;
    };

    // The work required before a canister upgrade begins.
    system func preupgrade() {
        // Debug.print("Starting pre-upgrade hook...");
        // _stableUsers := Iter.toArray(_users.entries());
        _stableDatastoreCanisterIds := List.toArray(_datastoreCanisterIds);
        _stableFileTreeRegistry := Iter.toArray(_fileTreeRegistry.entries());
        _stableFileTreeStorage := Iter.toArray(_fileTreeStorage.entries());
        // Debug.print("pre-upgrade finished.");
    };

    // The work required after a canister upgrade ends.
    system func postupgrade() {
        // Debug.print("Starting post-upgrade hook...");
        // _stableUsers := [];
        _stableDatastoreCanisterIds := [];
        _stableFileTreeRegistry := [];
        _stableFileTreeStorage := [];
        // Debug.print("post-upgrade finished.");
    };

    public func resetStorageList() : async () {
        _datastoreCanisterIds := List.fromArray([]);
        _stableDatastoreCanisterIds := [];
    };

    public query ({caller}) func whoami() : async Text {
        return Principal.toText(caller);
    };
};