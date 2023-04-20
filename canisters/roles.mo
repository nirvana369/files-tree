import Types "types";

import Buffer "mo:base/Buffer";
import Principal "mo:base/Principal";

module {
    

    public func init(p : Principal, admins : [Principal], storages : [Principal]) : Role {
        let r = Role(p);
        r.setAdmins(admins);
        r.setStorages(storages);
        r;
    };

    public class Role(p : Principal) = this {

        var superAdmin = p;
        var _admin = Buffer.Buffer<Principal>(0);
        var _storages = Buffer.Buffer<Principal>(0);

        public func setAdmins(list : [Principal]) {
            _admin := Buffer.fromArray(list);
        };

        public func addAdmin(p : Principal) {
            switch(Buffer.indexOf<Principal>(p, _admin, Principal.equal)) {
                case(null) { _admin.add(p); };
                case(?index) { };
            };
        };

        public func iterAdmins(f : (Principal) -> ()) {
            for (p in _admin.vals()) {
                 f(p);
            }
        };

        public func asynIterAdmins(f : (Principal) -> async ()) : async () {
            for (p in _admin.vals()) {
                await f(p);
            }
        };

        public func verify(p : Principal) : ?Types.Roles {
            if (p == Principal.fromText("2vxsx-fae")) return ?(#anonymous); //
            if (p == superAdmin) return ?(#superadmin); //
            switch(Buffer.indexOf<Principal>(p, _admin, Principal.equal)) {
                case(null) {  };
                case(?index) { return ?(#admin) };
            };
            switch(Buffer.indexOf<Principal>(p, _storages, Principal.equal)) {
                case(null) {  };
                case(?index) { return ?(#storage) };
            };
            return ?(#user);
        };

        public func getAdmins() : [Principal] {
            Buffer.toArray(_admin);
        };

        public func setStorages(list : [Principal]) {
            _storages := Buffer.fromArray(list);
        };

        public func addStorage(p : Principal) {
            switch(Buffer.indexOf<Principal>(p, _storages, Principal.equal)) {
                case(null) { _storages.add(p); };
                case(?index) { };
            };
        };

        public func asynIterStorages(f : (Principal) -> async ()) : async () {
            for (p in _storages.vals()) {
                await f(p);
            }
        };

        public func iterStorages(f : (Principal) -> ()) {
            for (p in _storages.vals()) {
                 f(p);
            }
        };

        public func getStorages() : [Principal] {
            Buffer.toArray(_storages);
        };

        public func setSuperAdmin(p : Principal) {
            superAdmin := p;
        };

        public func getSuperAdmin() : Principal {
            return superAdmin;
        };

        public func getRoles() : [(Principal, Types.Roles)] {
            let buf = Buffer.Buffer<(Principal, Types.Roles)>(1);
            buf.add((superAdmin, #superadmin));
            iterStorages(func (s) {
                buf.add((s, #storage));
            });
            iterAdmins(func (a) {
                buf.add((a, #admin));
            });
            Buffer.toArray(buf);
        };
    };
}