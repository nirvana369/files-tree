import Types "types";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import HashMap "mo:base/HashMap";
import Buffer "mo:base/Buffer";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Nat "mo:base/Nat";
import Hash "mo:base/Hash";


module {


    // public func merge(name : Text, ftA : Types.MutableFileTree, ftB : Types.MutableFileTree) : Types.MutableFileTree {

    // };

    // private func _asyncIter(level : Nat, path : Text, fileTree : FileTree, f : (Text, FileTree) -> async ()) : async () {
    //     switch (fileTree.getType()) {
    //         case (#file) {
    //             await f(path # "/" # fileTree.getName(), fileTree);
    //         };
    //         case (#directory) {
    //             await f(path # "/" # fileTree.getName(), fileTree);
    //             for (child in fileTree.getChilds().vals()) {
    //                 await _asyncIter(level + 1, path # "/" # fileTree.getName(), child, f);
    //             };
    //         };
    //     };
    // };

    // private func _iter(level : Nat, path : Text, fileTree : FileTree, f : (Text, FileTree) -> ()) {
    //     switch (fileTree.getType()) {
    //         case (#file) {
    //             f(path # "/" # fileTree.getName(), fileTree);
    //         };
    //         case (#directory) {
    //             f(path # "/" # fileTree.getName(), fileTree);
    //             for (child in fileTree.getChilds().vals()) {
    //                 _iter(level + 1, path # "/" # fileTree.getName(), child, f);
    //             };
    //         };
    //     };
    // };

    private func _iterFiles(fileTree : FileTree, callback : (FileTree) -> ()) {
        _iter(fileTree, func (f) {
            if (f.getType() == #file) {
                callback(f);
            };
        });
    };

    private func _asyncIterFiles(fileTree : FileTree, f : (Types.MutableFileTree) -> async ()) : async () {
        await _asyncIter(fileTree, func (x : FileTree) : async () {
            if (x.getType() == #file) {
                await f(x.get());
            };
        });
    };

    // private func _iterDirs(fileTree : Types.MutableFileTree, f : (Types.MutableFileTree) -> ()) {
        
    // };

    public type FilterType = {
        #name : Text;
        #id : Nat;
        #hash : Text;
        #size : Nat;
    };

    public class FileManager(ft : Types.FileTree) {
        
        let fileTree : FileTree = FileTree(0, "", _convert2MutableFileTree(ft));
        let paths = HashMap.HashMap<Text, FileTree>(0, Text.equal, Text.hash);
        var isInit = false;

        public func verify() : Types.FileTree {
            // check children:
            // 1/ 2 folder in a folder have same name
            // 2/ 2 file in a folder have same name or same hash
            if (not _verify(fileTree)) {
                Debug.trap("File Tree has 2 folder or file with same name in a folder")
            };
            _convert2FileTree(fileTree.update());
        };

        // make sure in a folder not have 2 folder or 2 file with same name
        private func _verify(f : FileTree) : Bool {
            let buf = f.getChilds();
            for (i in Iter.range(0, buf.size() - 2)) {
                for (j in Iter.range(i + 1, buf.size() - 1)) {
                    let f1 = buf.get(i);
                    let f2 = buf.get(j);
                    if (f1.getType() == f2.getType() and f1.getName() == f2.getName()) {
                        return false;
                    }
                };
            };
            for (c in buf.vals()) {
                if (not _verify(c)) {
                    return false;
                };
            };
            return true;
        };

        public func init() {
            // update parent for all child
            let f = fileTree.update();
            for (k in paths.keys()) {
                paths.delete(k);
            };
            _iter(fileTree, func (tree) : () {
                paths.put(tree.getPath(), tree);
            });
            isInit := true;
        };

        public func move(pathA : Text, pathB : Text) {
            let fA = paths.get(pathA);
            let fB = paths.get(pathB);
            
            switch (fA, fB) {
                case(null, null) {
                    Debug.trap("Both path " # pathA # " and " # pathB # " not exist");
                };
                case(?a, null) {
                    Debug.trap(pathB # " not exist ");
                };
                case(null, ?b) {
                    Debug.trap(pathA # " not exist ");
                };
                case ((?a, ?b)) {
                    b.addChild(a);
                };
            };
        };

        public func delete(path : Text) {
            // make sure call fileTree.update() before -> because this func need call to get parent
            let f = paths.get(path);
            switch (f) {
                case null {
                    Debug.trap(path # " not exist");
                };
                case (?file) {
                    let parent = file.getParent();
                    switch(parent) {
                        case(?p) {
                            let ret = p.removeChild(file);
                            if (ret == 0) {
                                Debug.trap(path # " delete failed! nothing change");
                            };
                        };
                        case(null) { Debug.trap(path # " not have a parent") };
                    };
                };
            };
        };

        public func copy(pathA : Text) {

        };



        public func getPaths() : [Text] {
            Iter.toArray(paths.keys());
        };

        public func setRootId(id : Nat) {
            fileTree.setId(id);
        };

        public func iterFiles(f : (FileTree) -> ()) {
            _iterFiles(fileTree, f);
        };

        public func asyncIterFiles(f : (Types.MutableFileTree) -> async ()) : async () {
            await _asyncIterFiles(fileTree, f);
        };

        public func getListFile() : [Types.MutableFileTree] {
            let buf = Buffer.Buffer<Types.MutableFileTree>(1);
            // _iterFiles(fileTree, func (f) {
            //     buf.add(f.get());
            // });
            for (f in paths.vals()) {
                if (f.getType() == #file) {
                    buf.add(f.get());
                };
            };
            Buffer.toArray(buf);
        };

        public func getListPath() : [Text] {
            let buf = Buffer.Buffer<Text>(1);
            for (p in paths.keys()) {
                    buf.add(p);
            };
            Buffer.toArray(buf);
        };

        public func getListFileFreeze() : [Types.FileTree] {
            let buf = Buffer.Buffer<Types.FileTree>(1);
            _iterFiles(fileTree, func (f) {
                buf.add(_convert2FileTree(f.get()));
            });
            Buffer.toArray(buf);
        };

        public func freeze() : Types.FileTree {
            _convert2FileTree(fileTree.get());
        };

        private func _found(t : ?Types.FileType, f : FileTree, filterBy : ?FilterType) : Bool {
            var found = switch (t) {
                            case null true; // not need check file type
                            case (?ftype) f.getType() == ftype;
                        };
            found := (found and (switch (filterBy) {
                                    case null return true; // no filter
                                    case (?filter) {
                                        switch(filter) {
                                            case (#name(name)) {
                                                if (f.getName() == name) return true;
                                                return false;
                                            };
                                            case (#id(id)) {
                                                if (f.getId() == id) return true;
                                                return false;
                                            };
                                            case (#hash(h)) {
                                                if (f.getFileHash() == h) return true;
                                                return false;
                                            };
                                            case (_) { return true; };
                                        }
                                    };
                                }));
            return found;
        };

        

        public func find(t : ?Types.FileType, filterBy : ?FilterType, f : (Types.MutableFileTree) -> ()) {
            _iter(fileTree, func (tree) {
                if (_found(t, tree, filterBy)) {
                    f(tree.get());
                };
            });
        };

        public func getBy(t : ?Types.FileType, filterBy : ?FilterType) : ?Types.FileTree {
            var ret : ?Types.FileTree = null;
            _iter(fileTree, func (tree) {
                if (ret == null and _found(t, tree, filterBy)) {
                    ret := ?_convert2FileTree(tree.get());
                };
            });
            ret;
        };

        // File path : format /root/a/b/c/d.jpg
        public func findByPath(path : Text, f : (FileTree) -> ()) {
            switch (paths.get(path)) {
                case null {
                    _iter(fileTree, func (tree) {
                        if (path == tree.getPath()) {
                            f(tree);
                        };
                    });
                };
                case (?file) f(file); 
            };
        };
    };

    //////////////////////////////////////////
        
    public class FileTree(level : Nat, route : Text, obj : Types.MutableFileTree) = this {

        var path = route # "/" # obj.name;
        var parent : ?FileTree = null;
        let childs = Buffer.map<Types.MutableFileTree, FileTree>(Buffer.fromArray(obj.children), func(mTree) {
            FileTree(level + 1, path, mTree);
        });

        public func removeChild(child : FileTree) : Nat {
            let size = childs.size();
            childs.filterEntries(func(_, ftree) {
                not equal(child, ftree);
            });

            if (size != childs.size()) {
                _updateChild();
            };
            (size - childs.size());
        };

        public func update() : Types.MutableFileTree {
            _updateChild();
            obj;
        };

        public func get() : Types.MutableFileTree {
            obj;
        };

        public func canAddChild(file : FileTree) : Bool {
            // can't add root 
            switch(file.getParent()) {
                case(null) { 
                    // root
                    Debug.trap(file.getPath() # " is root");
                    // return false;
                }; 
                case(?parent) { 
                    // if this is parent -> dont need add
                    if (equal(parent, this)) {
                        Debug.trap(file.getPath() # " has parent is " # getPath());
                        // return false;
                    }
                };
            };
            
            // i'm a file, i can't add you
            if (obj.fType == #file) {
                Debug.trap(getPath() # " is file, please choose folder to add " # file.getPath());
                // return false;
            };
            // this is child of the file params 
            switch(file.findChild(this)) {
                case(?f) {
                    // compare f to self
                    Debug.trap(getPath() # " is child of " # file.getPath());
                    // return false;
                };
                case(null) { }// do nothing - it's ok to add;
            };
            true;
        };

        public func addChild(file : FileTree) {
            if (canAddChild(file)) {
                switch (file.getParent()) {
                    case (null) {};
                    case (?p) {
                        let ret = p.removeChild(file);
                        if (ret != 1) {
                            Debug.trap("addChild - call remove child but result so strange" # Nat.toText(ret));
                        };
                    };
                };
                file.setParent(this);
                childs.add(file);
                _updateChild();
            };
        };

        private func _updateChild() {
            for(child in childs.vals()) {
                child.setParent(this);
            };
            obj.children := Buffer.toArray(Buffer.map<FileTree, Types.MutableFileTree>(childs, func (ftree) {
                ftree.update();
            }));
        };



        public func updatePath(parentPath : Text) {
            path := parentPath # "/" # obj.name;
            for (child in childs.vals()) {
                child.updatePath(path);
            };
        };

        public func rename(name : Text) {
            obj.name := name;
            updatePath(_getParentPath(path));
        };

        public func setParent(p : FileTree) {
            parent := ?p;
            updatePath(p.getPath());
        };

        public func getParent() : ?FileTree {
            parent;
        };

        public func getChilds() : [FileTree] {
            Buffer.toArray(childs);
        };

        public func getPath() : Text {
            path;
        };

        public func getLevel() : Nat {
            return level;
        };

        public func getParentPath() : Text {
            switch(parent) {
                case null _getParentPath(path);
                case (?p) {
                    // p.getPath();
                    _getParentPath(path);
                };
            };
        };

        public func equal(x : FileTree, y : FileTree) : Bool {
            x.hash() == y.hash();
        };

        public func hash() : Hash.Hash {
            Text.hash(path);
        };

        public func getId() : Nat {
            obj.id;
        };

        public func setId(id : Nat) {
            obj.id := id;
        };

        public func getName() : Text {
            obj.name;
        };

        public func getFileHash() : Text {
            obj.hash;
        };

        public func getType() : Types.FileType {
            obj.fType;
        };

        public func putFile() : async () {
            if (obj.id == 0) {
                // put file
            };
        };

        public func getFile() : async ?Types.File {
            let canister : Types.FileStorage = actor (obj.canisterId);
            await canister.readFile(obj.id);
        };

        public func deleteFile() : async () {
            // when delete file -> all chunk will be delete too
        };

        public func putChunk(canister : Text) : async () {

        };

        public func getChunk(chunkId : Nat) : async () {

        };

        public func findChild(that : FileTree) : ?FileTree {
            if (that.getPath() == this.getPath() and 
                that.getName() == this.getName() and 
                that.getFileHash() == this.getFileHash() and
                that.getType() == this.getType()) { 
                return ?this;
            };

            for (child in childs.vals()) {
                switch(child.findChild(that)) {
                    case(?found) { return ?found };
                    case(null) { };
                };
            };
            return null;
        };
    };

    ////////////////////////////////////////////

    private func _iter(tree : FileTree, f : (FileTree) -> ()) {
            f(tree);
            for (child in tree.getChilds().vals()) {
                _iter(child, f);
            };
    };

    private func _asyncIter(tree : FileTree, f : (FileTree) -> async ()) : async () {
            await f(tree);
            for (child in tree.getChilds().vals()) {
                await _asyncIter(child, f);
            };
    };

    // private func _filePathLevel(path : Text) : Buffer.Buffer<Text> {
    //     let paths = Text.split(path, #char '/');
    //     Buffer.fromIter<Text>(paths);
    // };

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