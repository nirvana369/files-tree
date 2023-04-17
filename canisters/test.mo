import Types "types";
import FileManager "file-manager";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Buffer "mo:base/Buffer";
import HashMap "mo:base/HashMap";
import Hash "mo:base/Hash";
import Text "mo:base/Text";

actor {

    stable var fTree : ?Types.FileTree = null;

    public func add(f : Types.FileTree) {
        fTree := ?f;
    };

    public func get() : async Types.FileTree {
        let fileTree = switch (fTree) {
            case null Debug.trap("empty");
            case (?f) f;
        };
        let f = FileManager.FileManager(fileTree);
        f.init();
        f.freeze();
    };

    public func recursiveGetTree(pathA : Text, pathB : Text) : async [Types.FileTree] {

        let fileTree = switch (fTree) {
            case null Debug.trap("empty");
            case (?f) f;
        };
        let f = FileManager.FileManager(fileTree);
        f.init();
        f.getListFileFreeze();
    };

    public func recursiveGetPath(pathA : Text, pathB : Text) : async [Text] {

        let fileTree = switch (fTree) {
            case null Debug.trap("empty");
            case (?f) f;
        };
        let f = FileManager.FileManager(fileTree);
        f.init();
        f.getListPath();
    };

    public func testMove(pathA : Text, pathB : Text) : async Types.FileTree {

        let fileTree = switch (fTree) {
            case null Debug.trap("empty");
            case (?f) f;
        };
        let f = FileManager.FileManager(fileTree);
        f.init();
        f.move(pathA, pathB);
        f.freeze();
    };
    
}