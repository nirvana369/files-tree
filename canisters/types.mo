import Principal "mo:base/Principal";
import Result "mo:base/Result";

module {

    public type FileTreeType = {
        #directory;
        #file;
    };

    public type FileState = {
        #ready;
        #empty;
    };

    public type FileTree = {
        fId : ?Nat;
        fType : FileTreeType;
        fName : Text;
        fCanister : ?Text;
        fHash : ?Text;
        fState : FileState;
        children : ?[FileTree];
    };

    public type MutableFileTree = {
        var fId : ?Nat;
        var fType : FileTreeType;
        var fName : Text;
        var fCanister : ?Text;
        var fHash : ?Text;
        var fState : FileState;
        var children : ?[MutableFileTree];
    };

    public type File = {
        fId : ?Nat;
        fName : Text;
        fHash : ?Text;
        fData : ?[Nat8];
        fState : FileState;
        fOwner : Principal;
    };

    public type FileChunk = {
        fId : Nat;
        fChunkId : Nat;
        fTotalChunk : Nat;
        fData : [Nat8];
        fOwner : Principal;
    };

    public type FileStorage = actor {
        // proxyPutFile : shared (Principal, Nat, [Nat8]) -> async Result.Result<Nat, Text>;
        // proxyGetFile : query (Principal, Nat) -> async Result.Result<File, Text>;
        // proxyDeleteFile : shared (Principal, Nat) -> async Result.Result<Nat, Text>;
        registerFile : shared (file : File) -> async File;
        getCanisterFilesAvailable : shared () -> async Nat;
        getCanisterMemoryAvailable : shared () -> async Nat;
        // getCanisterId : shared () -> async Principal;
        // putFile : shared (Nat, [Nat8]) -> async Result.Result<Nat, Text>;
        getFile : query (Principal, Nat) -> async Result.Result<File, Text>;
        deleteFile : shared (Principal, Nat) -> async Result.Result<Nat, Text>;
        streamUpFile : shared (FileChunk) -> async Result.Result<FileState, Text>;
        streamDownFile : shared (Principal, Nat, Nat) -> async Result.Result<FileChunk, Text>;
        removeChunksCache : shared (Nat) -> async ();
        // proxyStreamUpFile : shared (FileChunk) -> async Result.Result<(), Text>;
        // proxyStreamDownFile : shared (Nat, Nat) -> async Result.Result<FileChunk, Text>;
        // whoami : query () -> async Text;
    };

}