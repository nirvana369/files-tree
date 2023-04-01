import Principal "mo:base/Principal";
import Result "mo:base/Result";

module {

    public type FileTreeType = {
        #directory;
        #file;
    };

    public type FileTree = {
        fId : ?Nat;
        fType : FileTreeType;
        fName : Text;
        fCanister : ?Text;
        fHash : ?Text;
        fData : ?[Nat8];
        children : ?[FileTree];
    };

    public type MutableFileTree = {
        var fId : ?Nat;
        var fType : FileTreeType;
        var fName : Text;
        var fCanister : ?Text;
        var fHash : ?Text;
        var fData : ?[Nat8];
        var children : ?[MutableFileTree];
    };

    public type FileState = {
        #ready;
        #empty;
    };

    public type File = {
        fId : ?Nat;
        fName : Text;
        fHash : ?Text;
        fData : ?[Nat8];
        fState : FileState;
    };

    public type FileStorage = actor {
        registerFileOwner : shared (owner : Principal, file : File) -> async File;
        deleteFile : shared Nat -> async Result.Result<Nat, Text>;
        getCanisterFilesAvailable : shared () -> async Nat;
        getCanisterId : shared () -> async Principal;
        getCanisterMemoryAvailable : shared () -> async Nat;
        putFile : shared (Nat, [Nat8]) -> async Result.Result<Nat, Text>;
        streamFile : shared (Nat, Nat, [Nat8]) -> async Result.Result<Nat, Text>
    };
}