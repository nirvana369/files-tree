import Principal "mo:base/Principal";
import Result "mo:base/Result";

module {

    public type FileType = {
        #directory;
        #file;
    };

    public type FileState = {
        #ready;
        #empty;
    };

    public type FileTree = {
        id : Nat;
        fType : FileType;
        name : Text;
        canisterId : Text;
        hash : Text;
        state : FileState;
        size : Nat;
        totalChunk : Nat;
        children : [FileTree];
    };

    public type MutableFileTree = {
        var id : Nat;
        var fType : FileType;
        var name : Text;
        var canisterId : Text;
        var hash : Text;
        var state : FileState;
        var size : Nat;
        var totalChunk : Nat;
        var children : [MutableFileTree];
    };

    public type File = {
        rootId : Nat;
        id : Nat;
        name : Text;
        hash : Text;
        chunks : [ChunkInfo];
        totalChunk : Nat;
        size : Nat;
        state : FileState;
        owner : Principal;
        lastTimeUpdate : Int;
    };

    public type ChunkInfo = {
        canisterChunkId : Nat;
        canisterId : Text;
        chunkOrderId : Nat;
    };

    public type FileChunk = {
        fileId : Nat;
        chunkOrderId : Nat;
        data : [Nat8];
    };

    public type FileStorage = actor {
        putFile : shared (file : File) -> async File;
        getCanisterFilesAvailable : shared () -> async Nat;
        getCanisterMemoryAvailable : shared () -> async Nat;
        // getCanisterId : shared () -> async Principal;
        readFile : query (Nat) -> async ?File;
        deleteFile : shared (Nat) -> async Result.Result<Nat, Text>;
        streamUp : shared (Text, FileChunk) -> async ?Nat;
        streamDown : query (Nat) -> async ?FileChunk;
        eventHandler : shared (Event) -> async ();
        deleteChunk : shared (Nat) -> async ();
        // whoami : query () -> async Text;
    };

    public type EventBus = actor {
        eventHandler : query (Event) -> async ();
    };

    public type Event = {
        #StreamUpChunk : (Nat, ChunkInfo);      //  #UpdateFileState(FileId, ChunkId, ChunkCanister, ChunkOrderId); -> update chunk info to file metadata
        #UpdateFileState : (Nat, Nat);   //  #UpdateFileTreeState(FileTreeId, FileId); -> update state file to ready
        #SyncCache : (Text, Nat);  // sync cache file id, chunk id - speed up streaming
        #DeleteChunk : (Text, Nat); // canister id, chunkid
    };

    //HTTP
    public type HeaderField = (Text, Text);
    public type HttpResponse = {
        status_code: Nat16;
        headers: [HeaderField];
        body: Blob;
        streaming_strategy: ?HttpStreamingStrategy;
        upgrade : ?Bool;
    };
    public type HttpRequest = {
        method : Text;
        url : Text;
        headers : [HeaderField];
        body : Blob;
    };
    public type HttpStreamingCallbackToken =  {
        content_encoding: Text;
        index: Nat;
        key: Text;
        sha256: ?Blob;
    };

    public type HttpStreamingStrategy = {
        #Callback: {
            callback: shared (HttpStreamingCallbackToken) -> async (HttpStreamingCallbackResponse);
            token: HttpStreamingCallbackToken;
        };
    };

    public type HttpStreamingCallbackResponse = {
        body: Blob;
        token: ?HttpStreamingCallbackToken;
    };
    
}