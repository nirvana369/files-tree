import Time "mo:base/Time";
import Int "mo:base/Int";
import Timer "mo:base/Timer";
import Text "mo:base/Text";
import HashMap "mo:base/HashMap";
import Deque "mo:base/Deque";
import Array "mo:base/Array";
import Buffer "mo:base/Buffer";
import Iter "mo:base/Iter";


module {
    public type ProfilerCanister = actor {
        push : ([ProfileResult]) -> async ();
    };

    public type Profile = {
        id : Text;
        action : Text;
        start : Int;
        end : Int;
    };

    public type ProfileResult = {
        id : Text;
        count : Nat;
        avgProcTime : Int;
        totalProcTime : Int;
    };

    public class Profiler(name : Text) = this {
        // let canister : ProfilerCanister = actor (canisterId);
        var queue = Deque.empty<Profile>();
        let res = Buffer.Buffer<(Text, ProfileResult)>(1);

        func pushProfile() : async () {
            let map : HashMap.HashMap<Text, ProfileResult> = HashMap.fromIter(res.vals(), 0, Text.equal, Text.hash);
            while (not Deque.isEmpty(queue)) {
                let item = Deque.popFront(queue);
                switch (item) {
                    case null { };
                    case (?p) {
                        queue := p.1;
                        switch (map.get(p.0.action)) {
                            case null {
                                map.put(p.0.action, {
                                    id = p.0.action;
                                    count = 1;
                                    totalProcTime = p.0.end - p.0.start;
                                    avgProcTime = p.0.end - p.0.start;
                                });
                            };
                            case (?c) {
                                let totalProc = c.totalProcTime + (p.0.end - p.0.start);
                                let avgProc = totalProc / (c.count + 1);
                                map.put(p.0.action, {
                                    id = p.0.action;
                                    count = c.count + 1;
                                    totalProcTime = totalProc;
                                    avgProcTime = avgProc;
                                });
                            };
                        };
                    };
                };
            };
            for (i in map.entries()) {
                res.add(i);
            }
        };

        let timer = Timer.recurringTimer(#seconds (5), pushProfile);

        public func push(funcName : Text) : Profile {
            let t = Time.now();
            let act = name # "." # funcName;
            return {
                id = act # "." # Int.toText(t);
                action = act;
                start = t;
                end = 0;
            };
        };

        public func pop(p : Profile) {
            let obj : Profile = {
                id = p.id;
                action = p.action;
                start = p.start;
                end = Time.now();
            };
            queue := Deque.pushBack<Profile>(queue, obj);
        };

        public func clear() {
            res.clear();
        };

        public func get() : [ProfileResult] {
            Iter.toArray<ProfileResult>(Buffer.map<(Text, ProfileResult), ProfileResult>(res, func (entry) {
                entry.1;
            }).vals());
        };
    };
}