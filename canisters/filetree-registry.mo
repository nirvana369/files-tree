import FileStorage "file-storage";
import ICType "IC";
import Types "types";
import Utils "file-manager";

import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import List "mo:base/List";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Nat32 "mo:base/Nat32";
import Hash "mo:base/Hash";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";
import Option "mo:base/Option";
import Blob "mo:base/Blob";
import Char "mo:base/Char";
import Text "mo:base/Text";
import Time "mo:base/Time";


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
    var IdGenFile : Nat = 0;

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


    public func grantCanisterStorageCallPermission() {

    };

    public shared ({caller}) func eventHandler(event : Types.Event) : async () {
        switch(event) {
            case(#UpdateFileState (fileTreeId, fileId)) {
                _updateFileState(fileTreeId, fileId, #ready);
            };
            case (_) { };
        };
    };

    private func _createFileId() : Nat {
        IdGenFile := IdGenFile + 1;
        IdGenFile;
    };

    public shared ({caller}) func verifyFileTree(fileTree : Types.FileTree) : async Types.FileTree {
        // get list file tree of caller

        // loop and recursive compare file name && file hash && 

        let fileManager = Utils.FileManager(fileTree);
        fileManager.verify();
    };

    public shared ({caller}) func createFileTree(fileTree : Types.FileTree) : async Result.Result<Types.FileTree, Text> {
        let fileManager = Utils.FileManager(fileTree);
        IdGen := IdGen + 1;
        await fileManager.asyncIterFiles(func (f : Types.MutableFileTree) : async () {
            let file : Types.File = {
                        rootId = IdGen;
                        id = _createFileId();
                        name = f.name;
                        hash = f.hash;
                        chunks = [];
                        totalChunk = f.totalChunk;
                        state = #empty;
                        owner = caller;
                        size = f.size;
                        lastTimeUpdate = Time.now();
                    };
            let (storageCanisterId, registeredFile) = await _registerFile(file);
            f.id := registeredFile.id;
            f.canisterId := Principal.toText(storageCanisterId);
            f.state := registeredFile.state;
        });
        
        // update FileTree -> file will have canister id + id
        
        fileManager.setRootId(IdGen);
        let imutableFileTree = fileManager.freeze();
        // return result for client -> client call canister file storage by canister id + id file to upload direct
        _putRegistry(caller, IdGen);
        _putFileTree(IdGen, imutableFileTree);

        #ok(imutableFileTree);
    };

    private func _validate(f : Types.MutableFileTree) {
        if (f.hash == "") Debug.trap("Give me file hash to register file: " # f.name);
        if (f.size == 0) Debug.trap("Give me file size to register file: " # f.name);
        if (f.totalChunk == 0) Debug.trap("Give me file totalChunk to register file: " # f.name);
        if (f.name == "") Debug.trap("Give me file name to register file: " # f.name);
    };

    private func _verifyOwner(caller : Principal, id : Nat) : ?Types.FileTree {
        switch(_fileTreeRegistry.get(caller)) {
            case(?listId) {
                switch (Array.find<Nat>(listId, func x = x == id)) {
                    case null null;
                    case (?id) _fileTreeStorage.get(id);
                };
            };
            case(null) { null};
        };
    };

    public shared ({caller}) func updateFileTree(fileTree : Types.FileTree) : async Result.Result<Types.FileTree, Text> {
        // read file tree 
        let fTree = switch (_verifyOwner(caller, fileTree.id)) {
            case null return #err "File tree id is empty!";
            case (?tree) {
                tree;
            };
        };
        let fTreeId = fTree.id;
        let fileManager = Utils.FileManager(fileTree);
        let files  = fileManager.getListFile();
      
        for (f in files.vals()) {
            _validate(f);
            if (f.id <= 0) {
                let file : Types.File = {
                        rootId = fTreeId;
                        id = _createFileId();
                        name = f.name;
                        hash = f.hash;
                        chunks = [];
                        totalChunk = f.totalChunk;
                        state = #empty;
                        owner = caller;
                        size = f.size;
                        lastTimeUpdate = Time.now();
                    };
                    let (storageCanisterId, registeredFile) = await _registerFile(file);
                    f.id := registeredFile.id;
                    f.canisterId := Principal.toText(storageCanisterId);
                    f.state := registeredFile.state;
            } else {
                if (f.canisterId == "") {
                    return #err ("Where is my file ? #id: " # Nat.toText(f.id));
                } else {
                    let storageCanister : Types.FileStorage = actor(f.canisterId);
                    let ret = await storageCanister.readFile(f.id);
                    switch (ret) {
                        case (?state) {
                            f.state := state.state;
                        };
                        case (null) {
                            // file not exist -> wrong file id 
                            return #err ("file not exist -> wrong file id: " # Nat.toText(f.id));
                        };
                    };
                };
            };
        };
        let imutableFileTree = fileManager.freeze();
        // return result for client -> client call canister file storage by canister id + id file to upload direct
        _putFileTree(fTreeId, imutableFileTree);

        #ok(imutableFileTree);
    };


    public shared ({caller}) func deleteFileTree(id : Nat) : async Result.Result<Nat, Text> {
        let fTreeId = switch (_verifyOwner(caller, id)) {
            case null return #err "File tree id is empty!";
            case (?id) {
                id;
            };
        };
        switch (_getFileTree(id)) {
            case null #err "File tree are not exist!";
            case (?fTree) {
                let fileManager = Utils.FileManager(fTree);
                await fileManager.asyncIterFiles(func (f : Types.MutableFileTree) : async () {
                    if (f.canisterId != "" and f.id > 0) {
                        let storageCanister : Types.FileStorage = actor(f.canisterId);
                        let ret = await storageCanister.deleteFile(f.id);
                    }
                });
                _fileTreeStorage.delete(id);
                _removeRegistry(caller, id);
                #ok id;
            };
        };
    };

    // move a file/folder A to folder B
    public shared ({caller}) func moveFile(id: Nat, pathA : Text, pathB : Text) : async Result.Result<Types.FileTree, Text> {
        switch (_getFileTree(id)) {
            case null #err "File tree are not exist!";
            case (?fTree) {
                let fileManager = Utils.FileManager(fTree);
                fileManager.init();

                fileManager.move(pathA, pathB);
                let immutableFileTree = fileManager.freeze();
                _putFileTree(id, immutableFileTree);
                
                #ok (immutableFileTree);
            };
        };
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

    private func _removeRegistry(owner : Principal, id : Nat) {
        switch (_fileTreeRegistry.get(owner)) {
            case null {};
            case (?arr) {
                let buf = Buffer.fromArray<Nat>(arr);
                switch (Buffer.indexOf<Nat>(id, buf, Nat.equal)) {
                    case null { };
                    case (?id) {
                        let x = buf.remove(id);
                        _fileTreeRegistry.put(owner, Buffer.toArray(buf));
                    };
                };
            };
        };
    };

    public shared ({caller}) func removeChunksCache(canisterId : Text, id : Nat) : async () {
        // let canister : Types.FileStorage = actor(canisterId);
        // await canister.removeChunksCache(id);
    };

    public shared ({caller}) func streamUpFile(fileTreeId : Nat, fileId : Nat, fchunk : Types.FileChunk) : async Result.Result<Nat, Text> {
        
        let fileTree = switch (_verifyOwner(caller, fileTreeId)) {
            case null return #err "File not exist";
            case (?ft) ft;
        };
        let fileManager = Utils.FileManager(fileTree);
        let f = switch(fileManager.getBy(?#file, ?#id(fileId))) {
            case null return #err ("File " # Nat.toText(fileId) # " not found");  
            //
            case (?file) {
                file;
            };
        };

        if (f.canisterId == "") {
            return #err ("File " # Nat.toText(fileId) # " canister not found");
        };
        let (storageCanisterId, storageCanister) = await _getCurrentDataStorage();
        let ret = await storageCanister.streamUp(f.canisterId, fchunk);
        switch(ret) {
            case null #err "Stream up chunk data failed";
            case (?canisterChunkId) #ok canisterChunkId;
        };
    };

    private func _updateFileState(id : Nat, fileId : Nat, state : Types.FileState) {
        let fileTree = _getFileTree(id);
        switch (fileTree) {
            case null {};
            case (?ft) {
                let fileManager = Utils.FileManager(ft);
                fileManager.find(?#file, ?#id(fileId), func (x) {
                        x.state := state;
                });
                let imutableFileTree = fileManager.freeze();
                _putFileTree(id, imutableFileTree);
            };
        };
    };

    private func _getFile(fileTree : Types.FileTree, fileId : Nat) : async ?Types.File {
        let fileManager = Utils.FileManager(fileTree);
        let f = switch(fileManager.getBy(?#file, ?#id(fileId))) {
            case null return null;
            //
            case (?file) {
                file;
            };
        };

        let canister : Types.FileStorage = actor (f.canisterId);
        let fileInfo = await canister.readFile(fileId);
        fileInfo;
    };
    
    public shared ({caller}) func streamDownFile(fileTreeId : Nat, fileId : Nat, chunkId : Nat) : async Result.Result<Types.FileChunk,Text> {
        let fileTree = switch (_verifyOwner(caller, fileTreeId)) {
            case null return #err "File not exist";
            case (?ft) ft;
        };
        let fileManager = Utils.FileManager(fileTree);
        let f = switch(fileManager.getBy(?#file, ?#id(fileId))) {
            case null return #err ("File " # Nat.toText(fileId) # " not found");  
            //
            case (?file) {
                file;
            };
        };

        if (f.canisterId == "") {
             return #err ("File " # Nat.toText(fileId) # " canister not found");
        };

        let canister : Types.FileStorage = actor (f.canisterId);
        let fileInfo = await canister.readFile(fileId);

        switch(fileInfo) {
            case(?f) {  
                let chunkInfo = Array.find<Types.ChunkInfo>(f.chunks, func c = c.chunkOrderId == chunkId);
                switch(chunkInfo) {
                    case(?info) {  
                        let chunkCanister : Types.FileStorage = actor (info.canisterId);
                        let chunk = await canister.streamDown(info.canisterChunkId);
                        switch(chunk) {
                            case(?value) { #ok value };
                            case(null) { return #err ("Chunk not exist: " # Nat.toText(chunkId))};
                        };
                    };
                    case(null) { 
                        return #err ("Chunk not found: TreeId=" # Nat.toText(fileTreeId) # "" # Nat.toText(fileId) # "" # Nat.toText(chunkId));
                    };
                };
            };
            case(null) { return #err ("File " # Nat.toText(fileId) # " metadata not found") };
        };
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

    private func _getCurrentDataStorage() : async (Principal, Types.FileStorage) {
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
        (storageCanisterId, storageCanister);
    };

    private func _registerFile(file : Types.File) : async (Principal, Types.File) {
        let (storageCanisterId, storageCanister) = await _getCurrentDataStorage();
        let registeredFile = await storageCanister.putFile(file);
        (storageCanisterId, registeredFile);
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

    // Http 
    let NOT_FOUND : Types.HttpResponse = {status_code = 404; headers = []; body = Blob.fromArray([]); streaming_strategy = null};
    let BAD_REQUEST : Types.HttpResponse = {status_code = 400; headers = []; body = Blob.fromArray([]); streaming_strategy = null};

    // public query func http_request(request : Types.HttpRequest) : async Types.HttpResponse {
    //     let path = Iter.toArray(Text.tokens(request.url, #text("/")));
    //     switch(_getParam(request.url, "index")) {
    //         case (?assetIdText) {
    //             let assetId = _textToNat32(assetIdText);
    //             switch(_assets.get(assetId)){
    //             case(?asset) {
    //                 return _processFile(assetId, asset)
    //             };
    //             case (_){};
    //             };
    //         };
    //         case (_){};
    //     };
    //     return {
    //         status_code = 200;
    //         headers = [("content-type", "text/plain")];
    //         body = Text.encodeUtf8 (
    //             "Cycle Balance:                            ~" # debug_show (Cycles.balance()/1000000000000) # "T\n"
    //             // "Storage:                                   " # debug_show (_assets.size()) # "\n"
    //         );
    //         streaming_strategy = null;
    //     };
    // };

    // public query func http_request_streaming_callback(token : Types.HttpStreamingCallbackToken) : async Types.HttpStreamingCallbackResponse {
    //     let fileTreeId = _textToNat(token.key);
    //     switch(_getFileTree(fileTreeId)){
    //         case(?ft) {
    //             let res = _streamContent(assetId, asset, token.index);
    //             return {
    //             body = res.0;
    //             token = res.1;
    //             };
    //         };
    //         case null return {body = Blob.fromArray([]); token = null};
    //     };
    // };

    private func _textToNat(t : Text) : Nat {
        var reversed : [Nat32] = [];
        for(c in t.chars()) {
            assert(Char.isDigit(c));
            reversed := Array.append<Nat32>([Char.toNat32(c)-48], reversed);
        };
        var total : Nat = 0;
        var place : Nat  = 1;
        for(v in reversed.vals()) {
            total += (Nat32.toNat(v) * place);
            place := place * 10;
        };
        total;
    };
};