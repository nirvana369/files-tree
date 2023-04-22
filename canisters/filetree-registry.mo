import FileStorage "file-storage";
import ICType "IC";
import Types "types";
import FileManager "file-manager";
import RBAC "roles";
import Profiler "profiler";

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

    let profiler = Profiler.Profiler("FileRegistry");

    let IC : ICType.Self = actor "aaaaa-aa";

    // The IC management canister.
    // See https://smartcontracts.org/docs/interface-spec/index.html#ic-management-canister
    // let IC : ICType.Self = actor "aaaaa-aa";

    // Currently, a single canister smart contract is limited to 4 GB of storage due to WebAssembly limitations.
    // To ensure that our datastore canister does not exceed this limit, we restrict memory usage to at most 2 GB because 
    // up to 2x memory may be needed for data serialization during canister upgrades. 
    let DATASTORE_CANISTER_CAPACITY : Nat = 2_000_000_000;

    // Size limit of each File is 1 MB.
    let CHUNK_DATA_SIZE = 1_000_000;

    let _numberOfDataPerCanister : Nat = DATASTORE_CANISTER_CAPACITY / CHUNK_DATA_SIZE;

    var IdGen : Nat = 0;
    var IdGenFile : Nat = 0;

    stable var UserIdGen : Nat = 0;

    stable var _currentDatastoreCanisterId : ?Principal = null;
    stable var _stableDatastoreCanisterIds : [Principal] = [];
    stable var _stableFileTreeRegistry : [(Principal, [Nat])] = [];
    stable var _stableFileTreeStorage : [(Nat, Types.FileTree)] = [];
    stable var _stableUserIdRegistry : [(Principal, Nat)] = [];

    let rm : RBAC.Role = RBAC.init(caller, [], _stableDatastoreCanisterIds);

    let _fileTreeStorage : HashMap.HashMap<Nat, Types.FileTree> = HashMap.fromIter<Nat, Types.FileTree>(_stableFileTreeStorage.vals(), 10, Nat.equal, Hash.hash);
    let _fileTreeRegistry : HashMap.HashMap<Principal, [Nat]> = HashMap.fromIter<Principal, [Nat]>(_stableFileTreeRegistry.vals(), 10, Principal.equal, Principal.hash);
    let _streamCache : HashMap.HashMap<Text, Types.FileChunk> = HashMap.HashMap(0, Text.equal, Text.hash);


    public shared ({caller}) func eventHandler(event : Types.Event) : async () {
        let p = profiler.push("eventHandler");
        // verify caller is storage canister -> only storage canister can handle this event message
        switch (rm.verify(caller)) {
            case(null or ?#anonymous or ?#user) { return };
            case (_) {};
        };
        switch(event) {
            case(#UpdateFileState (fileTreeId, fileId)) {
                let p = profiler.push("eventHandler.UpdateFileState");
                _updateFileState(fileTreeId, fileId, #ready);
                profiler.pop(p);
            };
            case(#SyncCache(fileHash, chunkId)) {
                let p = profiler.push("eventHandler.SyncCache");
                //get file
                // get chunk
                // put cache
                let fileTreeId = switch(_streamCache.get(fileHash)) {
                    case null {0};
                    case (?fileInfo) {
                        fileInfo.fileId;
                    };
                };
                switch (_getFileTree(fileTreeId)) {
                    case null {};
                    case (?ft) {
                        let fm = FileManager.init(ft);
                        let file = switch (fm.get(?#file, ?#hash(fileHash))) {
                            case null {};
                            case (?f) {
                                switch (await f.getChunk(chunkId, false)) {
                                    case (#err (e)) {};
                                    case (#ok (chunk)) {
                                        _streamCache.put(_keyStreamCache(fileHash, chunkId), chunk);
                                    };
                                }
                            };
                        };
                    }
                };
                profiler.pop(p);
            };
            case (_) { };
        };
    };

    private func notify(canisterId : Text, e : Types.Event) : async () {
        let p = profiler.push("notify");
        let registry : Types.EventBus = actor (canisterId);
        await registry.eventHandler(e);
        profiler.pop(p);
    };

    private func _createFileId() : Nat {
        IdGenFile := IdGenFile + 1;
        IdGenFile;
    };

    public shared ({caller}) func verifyFileTree(fileTree : Types.FileTree) : async Types.FileTree {
        let fileManager = FileManager.init(fileTree);
        fileManager.verify();
    };

    public shared ({caller}) func createFileTree(fileTree : Types.FileTree) : async Result.Result<Types.FileTree, Text> {
        let p = profiler.push("createFileTree");

        switch(rm.verify(caller)) {
            case (?#anonymous) return #err "Permission invalid";
            case (_) {};
        };
        let fileManager = FileManager.init(fileTree);
        IdGen := IdGen + 1;
        fileManager.setRootId(IdGen);

        // trap if not enough cycles
        let (storageCanisterId, storageCanister) = await _getCurrentDataStorage();
        var fileCreateFailed = 0;
        await fileManager.asyncIterFiles(func (file : FileManager.FileTree) : async () {
            let ret = await file.registerFile(storageCanisterId, IdGen, _createFileId(), caller);
            switch(ret) {
                case null {fileCreateFailed += 1};
                case (?file) {};
            }
        });
        
        let imutableFileTree = fileManager.freeze();

        _putRegistry(caller, fileManager.getRootId());
        _putFileTree(fileManager.getRootId(), imutableFileTree);
        
        profiler.pop(p);

        if (fileCreateFailed > 0) {
            // monitor this case
            let p = profiler.push("createFileTree.createFileFailed");
            profiler.pop(p);
        };
        #ok(imutableFileTree);
    };

    private func _validate(f : Types.MutableFileTree) {
        if (f.hash == "") Debug.trap("Give me file hash to register file: " # f.name);
        if (f.size == 0) Debug.trap("Give me file size to register file: " # f.name);
        if (f.totalChunk == 0) Debug.trap("Give me file totalChunk to register file: " # f.name);
        if (f.name == "") Debug.trap("Give me file name to register file: " # f.name);
    };

    private func _verifyOwner(caller : Principal, id : Nat) : ?Types.FileTree {
        switch(rm.verify(caller)) {
            case (?#superadmin or ?#admin or ?#storage) {
                _fileTreeStorage.get(id);
            };
            case (_) {
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
        };
        
    };

    public shared ({caller}) func updateFileTree(fileTree : Types.FileTree) : async Result.Result<Types.FileTree, Text> {
        let p = profiler.push("updateFileTree");
        // read file tree 
        let fTree = switch (_verifyOwner(caller, fileTree.id)) {
            case null return #err "Permission invalid!";
            case (?tree) {
                tree;
            };
        };
        let fTreeId = fTree.id;
        let fileManager = FileManager.init(fileTree);
        let files  = fileManager.getListFile();
      
        for (f in files.vals()) {
            _validate(f.get());
            if (f.getId() <= 0) {
                let (storageCanisterId, storageCanister) = await _getCurrentDataStorage();
                let ret = await f.registerFile(storageCanisterId, fTreeId, _createFileId(), caller);
                switch(ret) {
                    case null return #err ("Register file failed: " # Nat.toText(f.getId()));
                    case (?file) {};
                }
            } else {
                let ret = await f.getFile(false);
                switch (ret) {
                    case (?existedFile) {};
                    case (null) {
                        // file not exist -> wrong file id 
                        return #err ("file not exist -> wrong file id: " # Nat.toText(f.getId()));
                    };
                };
            };
        };
        let imutableFileTree = fileManager.freeze();
        // return result for client -> client call canister file storage by canister id + id file to upload direct
        _putFileTree(fTreeId, imutableFileTree);

        profiler.pop(p);

        #ok(imutableFileTree);
    };


    public shared ({caller}) func deleteFileTree(id : Nat) : async Result.Result<Nat, Text> {
        let p = profiler.push("deleteFileTree");

        let fTreeId = switch (_verifyOwner(caller, id)) {
            case null return #err "Permission invalid!";
            case (?id) {
                id;
            };
        };
        switch (_getFileTree(id)) {
            case null #err "File tree are not exist!";
            case (?fTree) {
                let fileManager = FileManager.init(fTree);

                await fileManager.asyncIterFiles(func (f : FileManager.FileTree) : async () {
                    await f.deleteFile();
                });

                _fileTreeStorage.delete(id);

                _removeRegistry(caller, id);
                
                profiler.pop(p);

                #ok id;
            };
        };
    };

    // move a file/folder A to folder B
    public shared ({caller}) func moveFile(fileTreeId: Nat, pathA : Text, pathB : Text) : async Result.Result<Types.FileTree, Text> {
        let p = profiler.push("moveFile");

        let fTree = switch (_verifyOwner(caller, fileTreeId)) {
            case null return #err "Permission invalid!";
            case (?tree) {
                let fileManager = FileManager.init(tree);

                fileManager.move(pathA, pathB);

                let immutableFileTree = fileManager.freeze();

                _putFileTree(fileTreeId, immutableFileTree);
                
                profiler.pop(p);

                #ok (immutableFileTree);
            };
        };
    };

    public query ({caller}) func getFileTree(id : Nat) : async Result.Result<Types.FileTree, Text> {
        let p = profiler.push("getFileTree");
        let fTree = switch (_verifyOwner(caller, id)) {
            case null return #err "Permission invalid!";
            case (?tree) {
                profiler.pop(p);

                #ok (tree);
            };
        };
    };

    public query ({caller}) func getListFileTree() : async Result.Result<[Types.FileTree], Text> {
        let p = profiler.push("getListFileTree");
        switch (_fileTreeRegistry.get(caller)) {
            case null {
                #err "Permission invalid!";
            };
            case (?arr) {
                let fTree = Array.mapFilter<Nat, Types.FileTree>(arr, func(id) {
                    _getFileTree(id);
                });
                profiler.pop(p);
                #ok fTree;
            };
        };
    };

    public shared ({caller}) func streamUpFile(fileTreeId : Nat, fileId : Nat, fchunk : Types.FileChunk) : async Result.Result<Nat, Text> {
        let p = profiler.push("streamUpFile");

        let fileTree = switch (_verifyOwner(caller, fileTreeId)) {
            case null return #err "Permission invalid!";
            case (?ft) ft;
        };
        let fileManager = FileManager.init(fileTree);
        let file = switch(fileManager.get(?#file, ?#id(fileId))) {
            case null return #err ("File " # Nat.toText(fileId) # " not found");  
            //
            case (?file) {
                file;
            };
        };

        file._assertCanisterId();
        let (storageCanisterId, storageCanister) = await _getCurrentDataStorage();
        // after put chunk, storage canister will notify to file storage canister to update file state
        let ret = await storageCanister.streamUp(file.getCanisterId(), fchunk);
        profiler.pop(p);

        switch(ret) {
            case null #err "Stream up chunk data failed";
            case (?canisterChunkId) #ok canisterChunkId;
        };
    };
    
    public shared ({caller}) func streamDownFile(fileTreeId : Nat, fileId : Nat, chunkId : Nat) : async Result.Result<Types.FileChunk, Text> {
        let p = profiler.push("streamDownFile");

        let fileTree = switch (_verifyOwner(caller, fileTreeId)) {
            case null return #err "Permission invalid!";
            case (?ft) ft;
        };
        let fileManager = FileManager.init(fileTree);
        let file = switch(fileManager.get(?#file, ?#id(fileId))) {
            case null return #err ("File " # Nat.toText(fileId) # " not found");  
            //
            case (?file) {
                file;
            };
        };
        profiler.pop(p);
        await file.getChunk(chunkId, false);
    };

    // internal func
    
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

    private func _updateFileState(id : Nat, fileId : Nat, state : Types.FileState) {
        let fileTree = _getFileTree(id);
        switch (fileTree) {
            case null {};
            case (?ft) {
                let fileManager = FileManager.init(ft);
                fileManager.find(?#file, ?#id(fileId), func (x) {
                        x.state := state;
                });
                let imutableFileTree = fileManager.freeze();
                _putFileTree(id, imutableFileTree);
            };
        };
    };

    private func checkStorageAvailable() : async ?Principal {
        for (canisterId in rm.getStorages().vals()) {
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

    public shared func getStorageInfo() : async [{id:Text; mem: Text}] {
        let buf = Buffer.Buffer<{id: Text; mem : Text;}>(1);
        await rm.asynIterStorages(func (s : Principal) : async () {
            let canister : Types.FileStorage = actor(Principal.toText(s));
            let memAvailable = await canister.getCanisterMemoryAvailable();
            buf.add({id = Principal.toText(s); mem = Nat.toText(memAvailable);});
        });
        Buffer.toArray(buf);
    };

    public shared ({caller}) func getServerInfo() : async [{id:Text; cycle: Text}] {
        [{id = Principal.toText(Principal.fromActor(this)); cycle = Nat.toText((Cycles.balance()/1000000000000)) # " T cycles"}];
    };

    private func _generateFileStorage() : async Result.Result<Principal,Text>{
        let p = profiler.push("_generateFileStorage");
        try {
            rm.addAdmin(Principal.fromActor(this));
            Cycles.add(4_000_000_000_000);
            let fileStorageCanister = await FileStorage.FileStorage(rm.getAdmins(), rm.getStorages());
            let canisterId = Principal.fromActor(fileStorageCanister);

            _currentDatastoreCanisterId := ?canisterId;
            rm.addStorage(canisterId);

            let settings: ICType.CanisterSettings = { 
                controllers = rm.getAdmins();
            };
            let params: ICType.UpdateSettings = {
                canister_id = canisterId;
                settings = settings;
            };
            await IC.update_settings(params);

            
            // notify all storage add new storage
            await rm.asynIterStorages(func (s : Principal) : async () {
                await notify(Principal.toText(s), #SyncRole(rm.getRoles()));
            });
            profiler.pop(p);

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

    public shared(msg) func getCanisterId() : async Text {
        let canisterId = Principal.toText(Principal.fromActor(this));
        return canisterId;
    };

    public shared ({caller}) func addAdmin(p : Principal) {
        switch (rm.verify(caller)) {
            case (?#admin or ?#superadmin) {
                rm.addAdmin(p);
                await rm.asynIterStorages(func (s : Principal) : async () {
                    await notify(Principal.toText(s), #SyncRole(rm.getRoles()));
                });
            };
            case (_) {
                Debug.trap("Permission invalid!");
            };
        };
    };

    public shared ({caller}) func addStorage(p : Principal) {
        switch (rm.verify(caller)) {
            case (?#admin or ?#superadmin) {
                rm.addStorage(p);
                await rm.asynIterStorages(func (s : Principal) : async () {
                    await notify(Principal.toText(s), #SyncRole(rm.getRoles()));
                });
            };
            case (_) {
                Debug.trap("Permission invalid!");
            };
        };
    };

    // The work required before a canister upgrade begins.
    system func preupgrade() {
        // Debug.print("Starting pre-upgrade hook...");
        // _stableUsers := Iter.toArray(_users.entries());
        _stableDatastoreCanisterIds := rm.getStorages();
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

    public query ({caller}) func whoami() : async Text {
        return Principal.toText(caller);
    };

    public query func getRoles() : async [(Principal, Types.Roles)] {
        rm.getRoles();
    };

    // Http 
    let NOT_FOUND : Types.HttpResponse = {status_code = 404; headers = []; body = Blob.fromArray([]); upgrade = null; streaming_strategy = null};
    let BAD_REQUEST : Types.HttpResponse = {status_code = 400; headers = []; body = Blob.fromArray([]); upgrade = null; streaming_strategy = null};
    
    

    public shared func http_request_streaming_callback(token : Types.HttpStreamingCallbackToken) : async Types.HttpStreamingCallbackResponse {
        let fileHash = token.key;
        let chunkId = token.index;
        let fileTreeId = switch(_streamCache.get(fileHash)) {
            case (null) { 0 };
            case (?fileTreeInfo) {
                fileTreeInfo.fileId;
            }
        };
        let fileTree = switch (_getFileTree(fileTreeId)) {
            case null return {body = Blob.fromArray([]); token = null};
            case (?ft) {
                ft;
            }
        };
        let fm = FileManager.init(fileTree);
        let file = switch (fm.get(?#file, ?#hash(fileHash))) {
            case null return {body = Blob.fromArray([]); token = null};
            case (?f) f;
        };
        let p = profiler.push("http_request_streaming_callback." # fileHash # Nat.toText(chunkId));
        profiler.pop(p);
        switch(_streamCache.get(_keyStreamCache(fileHash, chunkId))){
            case(?chunkCache) {
                let p = profiler.push("http_request_streaming_callback.cache");
                profiler.pop(p);
                let res = await _streamContent(fileHash, chunkCache, file.getTotalChunk());
                return {
                    body = res.0;
                    token = res.1;
                };
            };
            case null {
                let p = profiler.push("http_request_streaming_callback.non-cache");
                profiler.pop(p);
                // init file tree
                // find file by hash
                // get chunk
                let chunkRet = await file.getChunk(chunkId, false);
                switch (chunkRet) {
                    case (#err (e)) {
                        return return {body = Text.encodeUtf8 (e); token = null};
                    };
                    case (#ok (chunk)) {
                        let res = await _streamContent(fileHash, chunk, file.getTotalChunk());
                        return {
                            body = res.0;
                            token = res.1;
                        };
                    };
                };
            };
        };
    };

    public query func http_request(request : Types.HttpRequest) : async Types.HttpResponse {
        let p = profiler.push("http_request");
        let path = Buffer.fromIter<Text>(Text.tokens(request.url, #text("/")));
        let buf = Buffer.fromIter<Text>(Text.tokens(path.get(path.size() - 1), #text("?")));
        let fHash = if (buf.size() > 1) {
            buf.get(0);
        } else {
            path.get(path.size() - 1);
        };
        let fTreeId = _textToNat(path.get(path.size() - 2));
        let owner = path.get(path.size() - 3);
        let chunkId = switch(_getParam(request.url, "chunkId")) {
            case null 0;
            case (?cid) _textToNat(cid);
        };
        let fileTree = switch(_verifyOwner(Principal.fromText(owner), fTreeId)) {
            case(?value) { value };
            case(null) { return _defaultResponse(?"File tree not exist!") };
        };
        let fm = FileManager.init(fileTree);
        switch(fm.get(?#file, ?#hash(fHash))) {
            case null return _defaultResponse(?("File not exist! : " # fHash));  
            case (?f) {
                // // support stream callback get file tree -> get file Hash
                _streamCache.put(fHash, {
                    fileId = fTreeId;
                    chunkOrderId = 0;
                    data = [];
                });
                // return await _processFile(f, chunkId);
            };
        };
        profiler.pop(p);

        return {
            upgrade = ?true;
            status_code = 200;
            headers = [("content-type", "text/plain")];
            body = Text.encodeUtf8 (
                "Cycle Balance:                            ~" # debug_show (Cycles.balance()/1000000000000) # "T\n"
            );
            streaming_strategy = null;
        }
    };

    private func _keyStreamCache(hash : Text, chunkId : Nat) : Text {
        hash # "_" # Nat.toText(chunkId);
    };
    
    private func _streamContent(fileHash : Text, chunk : Types.FileChunk, totalChunk : Nat) : async (Blob, ?Types.HttpStreamingCallbackToken) {
        let payload = Blob.fromArray(chunk.data);
        if (chunk.chunkOrderId > 0) {
            _streamCache.delete(_keyStreamCache(fileHash, chunk.chunkOrderId - 1));
        };
        if (chunk.chunkOrderId + 1 == totalChunk) {
            let p = profiler.push("_streamContent.lastChunk");
            // remove all cache
            _streamCache.delete(fileHash);
            profiler.pop(p);
            return (payload, null);
            
        };
        let p = profiler.push("_streamContent");

        await notify(Principal.toText(Principal.fromActor(this)), (#SyncCache(fileHash, chunk.chunkOrderId + 1)));

        let token = ?{
            content_encoding = "gzip";
            index = chunk.chunkOrderId + 1;
            sha256 = null;
            key = fileHash;
        };
        profiler.pop(p);
        return (payload, token);
    };

    private func _makeStreamingHttpResponse((payload : Blob, token : ?Types.HttpStreamingCallbackToken)) : async Types.HttpResponse {
        if (token == null) {
            return {
                upgrade = ?true;
                status_code = 200;
                headers = [/*("Content-Type", asset.ctype), ("cache-control", "public, max-age=15552000"), ("Content-Length", Nat.toText(contentLength))*/ 
                ("Transfer-Encoding", "gzip"), ("Access-Control-Allow-Origin", "*")
                ];
                body = payload;
                token = null;
                streaming_strategy = null;
            };
        };
        return {
            upgrade = ?true;
            status_code = 200;
            headers = [/*("Content-Type", asset.ctype), ("cache-control", "public, max-age=15552000"), ("Content-Length", Nat.toText(contentLength))*/ 
                ("Transfer-Encoding", "gzip"), ("Access-Control-Allow-Origin", "*")
                ];
            body = payload;
            streaming_strategy = ?#Callback({
            token = Option.unwrap(token);
            callback = http_request_streaming_callback;
            });
        };
    };

    private func _processFile(fm : FileManager.FileTree, chunkId : Nat) : async Types.HttpResponse {
        let p = profiler.push("_processFile");
        // if cache has chunk by hash & chunk id
        let ret = switch (_streamCache.get(_keyStreamCache(fm.getFileHash(), chunkId))) {
            case null {
                let chunkRet = await fm.getChunk(chunkId, false);
                switch (chunkRet) {
                    case (#err (e)) {
                        return _defaultResponse(?e);
                    };
                    case (#ok (chunk)) {
                        await _makeStreamingHttpResponse(await _streamContent(fm.getFileHash(), chunk, fm.getTotalChunk()));
                    };
                };
            };
            case (?chunk) {
                await _makeStreamingHttpResponse(await _streamContent(fm.getFileHash(), chunk, fm.getTotalChunk()));
            };
        };
        profiler.pop(p);
        ret;
    };

    public shared func http_request_update(request : Types.HttpRequest) : async Types.HttpResponse {
        let p = profiler.push("http_request_update");

        let path = Buffer.fromIter<Text>(Text.tokens(request.url, #text("/")));
        let fHash = Buffer.fromIter<Text>(Text.tokens(path.get(path.size() - 1), #text("?"))).get(0);
        let fTreeId = _textToNat(path.get(path.size() - 2));
        let owner = path.get(path.size() - 3);
        let chunkId = switch(_getParam(request.url, "chunkId")) {
            case null 0;
            case (?cid) _textToNat(cid);
        };
        let fileTree = switch(_verifyOwner(Principal.fromText(owner), fTreeId)) {
            case(?value) { value };
            case(null) { return _defaultResponse(?"File tree not exist!") };
        };
        let fm = FileManager.init(fileTree);
        switch(fm.get(?#file, ?#hash(fHash))) {
            case null return _defaultResponse(?("File not exist! : " # fHash));  
            case (?f) {
                // support stream callback get file tree -> get file Hash
                _streamCache.put(fHash, {
                    fileId = fTreeId;
                    chunkOrderId = 0;
                    data = [];
                });
                profiler.pop(p);
                return await _processFile(f, chunkId);
            };
        };
        return _defaultResponse(null);
    };

    private func _defaultResponse(err : ?Text) : Types.HttpResponse {
        switch(err) {
            case(?info) {  
                {
                    upgrade = null;
                    status_code = 200;
                    headers = [("content-type", "text/plain")];
                    body = Text.encodeUtf8 (info);
                    streaming_strategy = null;
                }
            };
            case(null) { 
                {
                    upgrade = null;
                    status_code = 200;
                    headers = [("content-type", "text/plain")];
                    body = Text.encodeUtf8 (
                        "Cycle Balance:                            ~" # debug_show (Cycles.balance()/1000000000000) # "T\n"
                        // "Storage:                                   " # debug_show (_assets.size()) # "\n"
                    );
                    streaming_strategy = null;
                }
            };
        };
    };

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

    private func _getParam(url : Text, param : Text) : ?Text {
        var _s : Text = url;
        Iter.iterate<Text>(Text.split(_s, #text("/")), func(x, _i) {
            _s := x;
        });
        Iter.iterate<Text>(Text.split(_s, #text("?")), func(x, _i) {
            if (_i == 1) _s := x;
        });
        var t : ?Text = null;
        var found : Bool = false;
        Iter.iterate<Text>(Text.split(_s, #text("&")), func(x, _i) {
        if (found == false) {
            Iter.iterate<Text>(Text.split(x, #text("=")), func(y, _ii) {
                if (_ii == 0) {
                    if (Text.equal(y, param)) found := true;
                } else if (found == true) t := ?y;
            });
        };
        });
        return t;
    };

    public func getProfiler() : async [Profiler.ProfileResult] {
        profiler.get();
    }
};