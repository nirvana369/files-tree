import Types "types";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";


module {

    type Node = {
        var id : Nat;
        var parent : Nat;
        var children : [Nat];
        var path : Text;
        var filePointer : Types.MutableFileTree;
    };

    // public func merge(name : Text, ftA : Types.MutableFileTree, ftB : Types.MutableFileTree) : Types.MutableFileTree {

    // };

    private func _asyncIter(level : Nat, path : Text, fileTree : Types.MutableFileTree, f : (Text, Types.MutableFileTree) -> async ()) : async () {
        switch (fileTree.fType) {
            case (#file) {
                await f(path # "/" # fileTree.name, fileTree);
            };
            case (#directory) {
                await f(path # "/" # fileTree.name, fileTree);
                if (fileTree.children.size() > 0) {
                    for (child in fileTree.children.vals()) {
                            await _asyncIter(level + 1, path # "/" # fileTree.name, child, f);
                        };
                };
            };
        };
    };

    private func _iter(level : Nat, path : Text, fileTree : Types.MutableFileTree, f : (Text, Types.MutableFileTree) -> ()) {
        switch (fileTree.fType) {
            case (#file) {
                f(path # "/" # fileTree.name, fileTree);
            };
            case (#directory) {
                f(path # "/" # fileTree.name, fileTree);
                if (fileTree.children.size() > 0) {
                    for (child in fileTree.children.vals()) {
                            _iter(level + 1, path # "/" # fileTree.name, child, f);
                        };
                };
            };
        };
    };

    private func _iterFiles(fileTree : Types.MutableFileTree, f : (Types.MutableFileTree) -> ()) {
        _iter(0, "", fileTree, func (p, x) {
            if (x.fType == #file) {
                f(x);
            };
        });
    };

    private func _asyncIterFiles(fileTree : Types.MutableFileTree, f : (Types.MutableFileTree) -> async ()) : async () {
        await _asyncIter(0, "", fileTree, func (p : Text, x : Types.MutableFileTree) : async () {
            if (x.fType == #file) {
                await f(x);
            };
        });
    };

    private func _iterDirs(fileTree : Types.MutableFileTree, f : (Types.MutableFileTree) -> ()) {
        _iter(0, "", fileTree, func (p, x) {
            if (x.fType == #directory) {
                f(x);
            };
        });
    };

    public class FileTree(ft : Types.FileTree) {
        
        let root : Types.MutableFileTree = _convert2MutableFileTree(ft);
        let nodes = HashMap.HashMap<Text, Node>(0, Text.equal, Text.hash);
        var id = 0;

        public func verify() : Types.FileTree {
            // check children:
            // 1/ 2 folder in a folder have same name
            // 2/ 2 file in a folder have same name or same hash
            if (not _verify(root)) {
                Debug.trap("File Tree has 2 folder or file with same name in a folder")
            };
            freeze();
        };

        private func _verify(f : Types.MutableFileTree) : Bool {
            let buf = Buffer.fromArray<Types.MutableFileTree>(f.children);
            for (i in Iter.range(0, buf.size() - 2)) {
                for (j in Iter.range(i + 1, buf.size() - 1)) {
                    let f1 = buf.get(i);
                    let f2 = buf.get(j);
                    if (f1.fType == f2.fType and f1.name == f2.name) {
                        return false;
                    }
                };
            };
            for (c in f.children.vals()) {
                if (not _verify(c)) {
                    return false;
                };
            };
            return true;
        };

        // must call before action : move file, delete file, copy file
        public func index() {
            // re-index
            id := 0;
            let keys = nodes.keys();
            for(k in keys) {
                nodes.delete(k);
            };
            _iter(0, "", root, func (path, x) {
                id += 1;
                let node : Node = {
                    var id = id;
                    var parent = 0;
                    var children = [];
                    var path = path;
                    var filePointer = x;
                };
                nodes.put(path, node);
            });

            for ((path, node) in nodes.entries()) {
                let parentPath = _getParentPath(path);
                switch (nodes.get(parentPath)) {
                    case null { if (parentPath != "") Debug.trap(parentPath); };
                    case (?parentNode) {
                        // add node parent
                        node.parent := parentNode.id;
                        // add children
                        let child = Buffer.fromArray<Nat>(parentNode.children);
                        child.add(node.id);
                        parentNode.children := Buffer.toArray<Nat>(child);
                    };
                };
            };
        };

        public func moveAtoB(pathFileA : Text, pathFileB : Text) {
            if (pathFileA == pathFileB) {
                Debug.trap("both path is the same");
            };
            let nA = nodes.get(pathFileA);
            let nB = nodes.get(pathFileB);
            switch ((nA, nB)) {
                case (null, null) {
                    Debug.trap("both path not exist");
                };
                case (null, nodeB) {
                    Debug.trap("file A path not exist");
                };
                case (nodeA, null) {
                    Debug.trap("file B path not exist");
                };
                case (?nodeA, ?nodeB) {
                    // can't move a folder to a file, or a file to a file
                    if (nodeB.filePointer.fType == #file) {
                        Debug.trap("can't move a folder to a file, or a file to a file");
                    };
                    // if A same type B is directory -> can't move parent to children -> check B is A's children ?
                    if (Text.contains(pathFileB, #text (pathFileA)) and 
                        nodeA.filePointer.fType == #directory and
                        nodeA.filePointer.fType == nodeB.filePointer.fType) {
                        Debug.trap("can't move a parent folder to a children folder");
                    };
                    if (nodeA.parent == nodeB.id) {
                        // do nothing A is B' children so don't need move
                        Debug.trap("B already have a child is A! Don't need move");
                    };
                    // SUPPORT : folder
                    // remove current parent of A
                    let nodeAParentPath = _getParentPath(nodeA.path);
                    switch (nodes.get(nodeAParentPath)) {
                        case null { 
                            if (nodeAParentPath == "") {    
                                Debug.trap("can't move a root folder to child " # nodeAParentPath)
                            } else { 
                                Debug.trap("Node A parent not found -> parent path: " # nodeAParentPath) 
                            };
                        };
                        case (?nodeAParent) {
                            // node remove child
                            let bufChild = Buffer.fromArray<Nat>(nodeAParent.children);
                            switch (Buffer.indexOf<Nat>(nodeA.id, bufChild, Nat.equal)) {
                                case null { Debug.trap("Node A id is not child of B") };
                                case (?id) {
                                    let x = bufChild.remove(id);
                                };
                            };
                            nodeAParent.children := Buffer.toArray(bufChild);
                            // file tree remove child
                            let bufChildFileTree = Buffer.fromArray<Types.MutableFileTree>(nodeAParent.filePointer.children);
                            let x = Buffer.indexOf<Types.MutableFileTree>(nodeA.filePointer, bufChildFileTree, func (treeX, treeY) : Bool {
                                    if (treeX.id != treeY.id) return false;
                                    if (treeX.fType != treeY.fType) return false;
                                    if (treeX.name != treeY.name) return false;
                                    if (treeX.hash != treeY.hash) return false;
                                    if (treeX.canisterId != treeY.canisterId) return false;
                                    if (treeX.state != treeY.state) return false;
                                    return true;
                            });
                            switch (x) {
                                case null { Debug.trap("Node A id is not child of B") };
                                case (?id) {
                                    let x = bufChildFileTree.remove(id);
                                };
                            };
                            nodeAParent.filePointer.children := Buffer.toArray(bufChildFileTree);
                               
                            
                        };
                    };

                    // add A into B
                    // add node A parent
                    nodeA.parent := nodeB.parent;
                    // add A to children of B
                    let buf = Buffer.fromArray<Nat>(nodeB.children);
                    buf.add(nodeA.id);
                    // add B file tree state -> add A child
                    let bufChildFileTree = Buffer.fromArray<Types.MutableFileTree>(nodeB.filePointer.children);
                    bufChildFileTree.add(nodeA.filePointer);
                    nodeB.filePointer.children := Buffer.toArray(bufChildFileTree);
                };
            };
        };

        public func getPaths() : [Text] {
            Iter.toArray(nodes.keys());
        };

        public func setRootId(fId : Nat) {
            root.id := fId;
        };

        public func iterFiles(f : (Types.MutableFileTree) -> ()) {
            _iterFiles(root, f);
        };

        public func asyncIterFiles(f : (Types.MutableFileTree) -> async ()) : async () {
            await _asyncIterFiles(root, f);
            // _asyncIterFiles
        };

        public func getListFile() : [Types.MutableFileTree] {
            let buf = Buffer.Buffer<Types.MutableFileTree>(1);
            _iterFiles(root, func (f) {
                buf.add(f);
            });
            Buffer.toArray(buf);
        };

        public func getListFileFreeze() : [Types.FileTree] {
            let buf = Buffer.Buffer<Types.FileTree>(1);
            _iterFiles(root, func (f) {
                buf.add(_convert2FileTree(f));
            });
            Buffer.toArray(buf);
        };

        public func nodeInfo() : [{
                                    id : Nat;
                                    parent : Nat;
                                    children : [Nat];
                                    path : Text;
                                    filePointer : Types.FileTree;}] 
        {
            
            let buf = Buffer.Buffer<{
                                    id : Nat;
                                    parent : Nat;
                                    children : [Nat];
                                    path : Text;
                                    filePointer : Types.FileTree;}>(1);
            for (node in nodes.vals()) {
                buf.add({
                    id = node.id;
                    parent = node.parent;
                    children = node.children;
                    path = node.path;
                    filePointer = _convert2FileTree(node.filePointer);
                });
            };
            Buffer.toArray(buf);
        };

        public func freeze() : Types.FileTree {
            _convert2FileTree(root);
        };

        public func findByName(name : Text, f : (Types.MutableFileTree) -> ()) {
            _iter(0, "", root, func (path, tree) {
                if (name == tree.name) {
                    f(tree);
                }
            });
        };

        public func findByHash(hash : Text, f : (Types.MutableFileTree) -> ()) {
            _iter(0, "", root, func (p, tree) {
                if (tree.hash == hash) {
                    f(tree);
                };
            });
        };

        public func findById(id : Nat, f : (Types.MutableFileTree) -> ()) {
            _iter(0, "", root, func (p, tree) {
                if (tree.id == id) {
                    f(tree);
                };
            });
        };

        // File path : format /root/a/b/c/d.jpg
        public func findByPath(path : Text, f : (Types.MutableFileTree) -> ()) {
            _iter(0, "", root, func (p, tree) {
                if (path == p) {
                    f(tree);
                };
            });
        };
    };

    private func _getParentPath(path : Text) : Text {
        let paths = Text.split(path, #char '/');
        let buf = Buffer.fromIter<Text>(paths);
        let f = buf.removeLast();
        let parentPath = Text.join("/",buf.vals());
        parentPath;
    };

    public func _convert2MutableFileTree(fileTree : Types.FileTree) : Types.MutableFileTree {
        let mut : Types.MutableFileTree = {
            var id = fileTree.id;
            var fType = fileTree.fType;
            var name = fileTree.name;
            var canisterId = fileTree.canisterId;
            var hash = fileTree.hash;
            var state = fileTree.state;
            var size = fileTree.size;
            var totalChunk = fileTree.totalChunk;
            var children = Array.map<Types.FileTree, Types.MutableFileTree>(fileTree.children, func (c) {
                    _convert2MutableFileTree(c);
                });
        };
        return mut;
    };

    public func _convert2FileTree(fileTree : Types.MutableFileTree) : Types.FileTree {
        let mut : Types.FileTree = {
            id = fileTree.id;
            fType = fileTree.fType;
            name = fileTree.name;
            canisterId = fileTree.canisterId;
            hash = fileTree.hash;
            state = fileTree.state;
            size = fileTree.size;
            totalChunk = fileTree.totalChunk;
            children = Array.map<Types.MutableFileTree, Types.FileTree>(fileTree.children, func (c) {
                    _convert2FileTree(c);
                });
        };
        return mut;
    };
}