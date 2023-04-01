import FileStorage "file-storage";
import ICType "IC";
import Types "types";

import Result "mo:base/Result";
import Principal "mo:base/Principal";
import Cycles "mo:base/ExperimentalCycles";
import List "mo:base/List";
import Array "mo:base/Array";
import Debug "mo:base/Debug";


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

    stable var _currentDatastoreCanisterId : ?Principal = null;
    stable var _stableDatastoreCanisterIds : [Principal] = [];

    var _dataStoreCanister : ?Types.FileStorage = null;
    var _datastoreCanisterIds = List.fromArray(_stableDatastoreCanisterIds);

    private func generateFileStorage() : async Result.Result<Principal,Text>{
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

            #ok (canisterId)
        } catch (e) {
            #err "An error occurred in generating a datastore canister."
        }
    };

    public shared ({caller}) func verifyFileTree(fileTree : Types.FileTree) : async Types.FileTree {
        // get list file tree of caller

        // loop and recursive compare file name && file hash && 

        fileTree;
    };

    private func recursiveRegisterFileTree(owner : Principal, fileTree : Types.MutableFileTree) : async () {
        switch (fileTree.fType) {
            case (#file) {
                let file : Types.File = {
                    fId = null;
                    fName = fileTree.fName;
                    fHash = fileTree.fHash;
                    fData = fileTree.fData;
                    fState = #empty;
                };
                let storageCanister = switch (_dataStoreCanister) {
                    case null {
                        // find in list ?
                        // create new ?
                        let ret = await generateFileStorage();
                        let canister = switch (ret) {
                            case (#ok(id)) {
                                let c : Types.FileStorage = actor(Principal.toText(id));
                                c;
                            };
                            case (#err e) {
                                Debug.trap("Can't create canister storage");
                            };
                        };
                        canister;
                    };
                    case (?canister) {
                       canister;
                    };
                };
                let registeredFile = await storageCanister.registerFileOwner(owner, file);
                fileTree.fId := registeredFile.fId;
                fileTree.fCanister := ?Principal.toText(Principal.fromActor(this));
            };
            case (#directory) {
                switch (fileTree.children) {
                    case null {
                        // do nothing
                    };
                    case (?childs) {
                        for (child in childs.vals()) {
                            await recursiveRegisterFileTree(owner, child);
                        };
                    };
                };
            };
        };
    };

    public shared ({caller}) func registerFileTree(fileTree : Types.FileTree) : async Result.Result<Types.FileTree,Text> {
        // read file tree 
        let mutFileTree = convert2MutableFileTree(fileTree);
        // call to storage to register file id
        await recursiveRegisterFileTree(caller, mutFileTree);
        // update FileTree -> file will have canister id + id
        IdGen := IdGen + 1;
        mutFileTree.fId := ?IdGen;
        let imutableFileTree = convert2FileTree(mutFileTree);
        // return result for client -> client call canister file storage by canister id + id file to upload direct

        #ok(imutableFileTree);
    };

    public query ({caller}) func getStorageCanisters() : async [Principal] {
        List.toArray(_datastoreCanisterIds);
    };

    private func convert2MutableFileTree(fileTree : Types.FileTree) : Types.MutableFileTree {
        let c = switch (fileTree.children) {
            case null null;
            case (?childs) {
                ?Array.map<Types.FileTree, Types.MutableFileTree>(childs, func (c) {
                    convert2MutableFileTree(c);
                });
            };
        };
        let mut : Types.MutableFileTree = {
            var fId = fileTree.fId;
            var fType = fileTree.fType;
            var fName = fileTree.fName;
            var fCanister = fileTree.fCanister;
            var fHash = fileTree.fHash;
            var fData = fileTree.fData;
            var children = c;
        };
        return mut;
    };

    private func convert2FileTree(fileTree : Types.MutableFileTree) : Types.FileTree {
        let c = switch (fileTree.children) {
            case null null;
            case (?childs) {
                ?Array.map<Types.MutableFileTree, Types.FileTree>(childs, func (c) {
                    convert2FileTree(c);
                });
            };
        };
        let mut : Types.FileTree = {
            fId = fileTree.fId;
            fType = fileTree.fType;
            fName = fileTree.fName;
            fCanister = fileTree.fCanister;
            fHash = fileTree.fHash;
            fData = fileTree.fData;
            children = c;
        };
        return mut;
    };

    // The work required before a canister upgrade begins.
    system func preupgrade() {
        // Debug.print("Starting pre-upgrade hook...");
        // _stableUsers := Iter.toArray(_users.entries());
        _stableDatastoreCanisterIds := List.toArray(_datastoreCanisterIds);
        // Debug.print("pre-upgrade finished.");
    };

    // The work required after a canister upgrade ends.
    system func postupgrade() {
        // Debug.print("Starting post-upgrade hook...");
        // _stableUsers := [];
        _stableDatastoreCanisterIds := [];
        // Debug.print("post-upgrade finished.");
    };
};