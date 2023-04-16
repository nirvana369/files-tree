import Types "types";
import FileManager "file-manager";

actor {
    public func test(fileTree : Types.FileTree) : async Types.FileTree {
        let f = FileManager.FileTree(fileTree);
        f.index();
        f.freeze();
    };

    public func testMove(fileTree : Types.FileTree, pathA : Text, pathB : Text) : async Types.FileTree {
        let f = FileManager.FileTree(fileTree);
        f.index();
        f.moveAtoB(pathA, pathB);
        f.freeze();
    };

    public func testPath(fileTree : Types.FileTree) : async [Text] {
        let f = FileManager.FileTree(fileTree);
        f.index();
        f.getPaths();
    };
    
    public func testNodeInfo(fileTree : Types.FileTree) : async [{
                                    id : Nat;
                                    parent : Nat;
                                    children : [Nat];
                                    path : Text;
                                    filePointer : Types.FileTree;}] 
    {
        let f = FileManager.FileTree(fileTree);
        f.index();
        f.nodeInfo();
    };
}