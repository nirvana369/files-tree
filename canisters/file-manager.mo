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

    private func _iter(path : Text, fileTree : Types.MutableFileTree, f : (Text, Types.MutableFileTree) -> ()) {
        switch (fileTree.fType) {
            case (#file) {
                f(path # "/" # fileTree.fName, fileTree);
            };
            case (#directory) {
                f(path # "/" # fileTree.fName, fileTree);
                switch (fileTree.children) {
                    case null {
                        // do nothing
                    };
                    case (?childs) {
                        for (child in childs.vals()) {
                            _iter(path # "/" # fileTree.fName, child, f);
                        };
                    };
                };
            };
        };
    };

    private func _iterFiles(fileTree : Types.MutableFileTree, f : (Types.MutableFileTree) -> ()) {
        _iter("", fileTree, func (p, x) {
            if (x.fType == #file) {
                f(x);
            };
        });
    };

    private func _iterDirs(fileTree : Types.MutableFileTree, f : (Types.MutableFileTree) -> ()) {
        _iter("", fileTree, func (p, x) {
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
            let children = switch (f.children) {
                case null [];
                case (?c) {
                    c;
                };
            };
            let buf = Buffer.fromArray<Types.MutableFileTree>(children);
            for (i in Iter.range(0, buf.size() - 2)) {
                for (j in Iter.range(i + 1, buf.size() - 1)) {
                    let f1 = buf.get(i);
                    let f2 = buf.get(j);
                    if (f1.fType == f2.fType and f1.fName == f2.fName) {
                        return false;
                    }
                };
            };
            for (c in children.vals()) {
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
            _iter("", root, func (path, x) {
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
                            switch (nodeAParent.filePointer.children) {
                                case null {};
                                case (?children) {
                                    let bufChildFileTree = Buffer.fromArray<Types.MutableFileTree>(children);
                                    let x = Buffer.indexOf<Types.MutableFileTree>(nodeA.filePointer, bufChildFileTree, func (x, y) : Bool {
                                            if (x.fId != y.fId) return false;
                                            if (x.fType != y.fType) return false;
                                            if (x.fName != y.fName) return false;
                                            if (x.fHash != y.fHash) return false;
                                            if (x.fCanister != y.fCanister) return false;
                                            if (x.fState != y.fState) return false;
                                            return true;
                                    });
                                    switch (x) {
                                        case null { Debug.trap("Node A id is not child of B") };
                                        case (?id) {
                                            let x = bufChildFileTree.remove(id);
                                        };
                                    };
                                    nodeAParent.filePointer.children := ?Buffer.toArray(bufChildFileTree);
                                };
                            };
                            
                        };
                    };

                    // add A into B
                    // add node A parent
                    nodeA.parent := nodeB.parent;
                    // add A to children of B
                    let buf = Buffer.fromArray<Nat>(nodeB.children);
                    buf.add(nodeA.id);
                    // add B file tree state -> add A child
                    let bufChildFileTree = switch (nodeB.filePointer.children) {
                        case null {
                            Buffer.Buffer<Types.MutableFileTree>(1);
                        };
                        case (?children) {
                            Buffer.fromArray<Types.MutableFileTree>(children);
                        };
                    };
                    bufChildFileTree.add(nodeA.filePointer);
                    nodeB.filePointer.children := ?Buffer.toArray(bufChildFileTree);
                };
            };
        };

        public func getPaths() : [Text] {
            Iter.toArray(nodes.keys());
        };

        public func setRootId(fId : Nat) {
            root.fId := ?fId;
        };

        public func iterFiles(f : (Types.MutableFileTree) -> ()) {
            _iterFiles(root, f);
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
            _iter("", root, func (path, x) {
                if (name == x.fName) {
                    f(x);
                }
            });
        };

        public func findByHash(hash : Text, f : (Types.MutableFileTree) -> ()) {
            _iter("", root, func (p, x) {
                switch (x.fHash) {
                    case (?h) {
                        if (h == hash) {
                            f(x);
                        };
                    };
                    case null {};
                };
            });
        };

        public func findById(id : Nat, f : (Types.MutableFileTree) -> ()) {
            _iter("", root, func (p, x) {
                switch (x.fId) {
                    case (?fid) {
                        if (fid == id) {
                            f(x);
                        };
                    };
                    case null {};
                };
            });
        };

        // File path : format /root/a/b/c/d.jpg
        public func findByPath(path : Text, f : (Types.MutableFileTree) -> ()) {
            _iter("", root, func (p, x) {
                if (path == p) {
                    f(x);
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

    public func _convert2FileTree(fileTree : Types.MutableFileTree) : Types.FileTree {
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
}