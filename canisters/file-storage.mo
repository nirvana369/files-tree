import Types "types";

import HashMap "mo:base/HashMap";
import Nat "mo:base/Nat";
import Hash "mo:base/Hash";
import Principal "mo:base/Principal";
import Result "mo:base/Result";


shared ({caller}) actor class FileStorage() = this {

    // Bind the caller and the admin
    let _admin : Principal = caller;

    type File = Types.File;

    var IdGenFile = 0;

    let DATASTORE_CANISTER_CAPACITY : Nat = 2_000_000_000;

    // Size limit of each note is 1 MB.
    let FILE_DATA_SIZE = 1_000_000;

    let _numberOfDataPerCanister : Nat = DATASTORE_CANISTER_CAPACITY / FILE_DATA_SIZE;

    // stable var _stableDatastores : [(Nat, FileTree)] = [];
    // let _datastores = HashMap.fromIter<Nat, FileTree>(_stableDatastores.vals(), 10, Nat.equal, Hash.hash);
    let _datastores : HashMap.HashMap<Nat, File> = HashMap.HashMap<Nat, File>(10, Nat.equal, Hash.hash);

    let _fileOwners : HashMap.HashMap<Nat, Principal> = HashMap.HashMap<Nat, Principal>(10, Nat.equal, Hash.hash);

    // registry canister need call this func first before user upload file with file id
    // file required hash md5
    public shared ({caller}) func registerFileOwner(owner : Principal, file : File) : async File {
        // only filetree-registry can call
        assert(caller == _admin);
        assert(file.fHash != null);
        IdGenFile := IdGenFile + 1;
        _fileOwners.put(IdGenFile, owner);
        
        // check if data available -> store data
        let hashEqual = true; // md5(file.fData) == file.fHash;
        // 

        let ftmp : File = {
                    fId = ?IdGenFile;
                    fName = file.fName;
                    fHash = file.fHash;
                    fData = file.fData;
                    fState = if (hashEqual == false and file.fData != null /* and file.fData.size() > 0*/) #empty else #ready;
                };
        _datastores.put(IdGenFile, ftmp);
        return ftmp;
    };
    
    public shared ({caller}) func streamFile(id : Nat, chunkId : Nat, chunkData : [Nat8]) : async Result.Result<Nat,Text> {
        switch(_fileOwners.get(id)) {
            case(null) { return #err "File id not registered" };
            case(?owner) { 
                if (owner != caller) {
                    return #err "You're not the file owner";
                };
            };
        };
        // process streaming

        //
        // if chunk == final -> check hash md5 -> return false if hash not same when register
        #ok(1);
    };

    public shared ({caller}) func putFile(id : Nat, data : [Nat8]) : async Result.Result<Nat,Text> {
        switch(_fileOwners.get(id)) {
            case(null) { return #err "File id not existed" };
            case(?owner) { 
                if (owner != caller) {
                    return #err "You're not the file owner";
                };
            };
        };
        switch (_datastores.get(id)) {
            case(null) { return #err "File not found!!! Need registered" };
            case(?file) { 
                // check hash md5 if hash not same when register -> error if has not equal

                // else if hash equal
                let ftmp = {
                    fId = file.fId;
                    fName = file.fName;
                    fHash = file.fHash;
                    fData = ?data;
                    fState = #ready;
                };
                _datastores.put(id, ftmp);
            };
        };
        
        #ok(id);
    };

    public query ({caller}) func getFile(id : Nat) : async Result.Result<File, Text> {
        switch (_fileOwners.get(id)) {
            case(null) { return #err "File id not registered" };
            case(?owner) { 
                if (owner != caller) {
                    return #err "You're not the file owner";
                };
            };
        };
        switch (_datastores.get(id)) {
            case(null) { return #err "File id not existed" };
            case(?file) { 
                #ok(file);
            };
        };
    };

    public shared ({caller}) func deleteFile(id : Nat) : async Result.Result<Nat, Text> {
        switch(_fileOwners.get(id)) {
            case(null) { return #err "File id not existed" };
            case(?owner) { 
                if (owner != caller) {
                    return #err "You're not the file owner";
                };
            };
        };
        _fileOwners.delete(id);
        #ok(id);
    };

    public shared(msg) func getCanisterId() : async Principal {
        let canisterId = Principal.fromActor(this);
        return canisterId;
    };

    public func getCanisterMemoryAvailable() : async Nat {
        return 4_000_000_000; // DATASTORE_CANISTER_CAPACITY - current memory used
    };

    public func getCanisterFilesAvailable() : async Nat {
        return 4_000_000_000 / _numberOfDataPerCanister; // (DATASTORE_CANISTER_CAPACITY - current memory used) / number item per canister
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
};