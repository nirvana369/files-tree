import { openDB, deleteDB, } from 'idb';
const DB_NAME = 'sw';
const DB_VERSION = 1.0;
const DB_DEFAULT_STORE = 'main';
const TTL_INDEX_NAME = 'ttl';
const TTL_INDEX_KEY_PATH = 'expireAt';
/**
 * Provides custom access to indexed db storage while still
 * keeping access to the underlying idb object.
 */
class Storage {
    constructor(idb, defaultStore) {
        this.idb = idb;
        this.defaultStore = defaultStore;
    }
    /**
     * Retrieves the underlying IDBPDatabase instance.
     */
    db() {
        return this.idb;
    }
    /**
     * Retrieves the default store name used for access.
     */
    store() {
        return this.defaultStore;
    }
    /**
     * Connects to the given database name from indexed db.
     *
     * @param name Name of the database to connect
     * @param version Version of the database
     * @param stores Stores options
     * @param onTerminated Callback when the browser interrupts the db connection
     */
    static async connect({ name = DB_NAME, version = DB_VERSION, stores = {}, onTerminated, } = {}) {
        var _a, _b;
        if (!(stores === null || stores === void 0 ? void 0 : stores.init) || !((_a = stores === null || stores === void 0 ? void 0 : stores.init) === null || _a === void 0 ? void 0 : _a.length)) {
            // we initialize the default store in case no other store is provided
            stores.init = [DB_DEFAULT_STORE];
        }
        const idb = await openDB(name, version, {
            async upgrade(database, oldVersion, _newVersion, transaction) {
                var _a;
                for (const createStore of (_a = stores.init) !== null && _a !== void 0 ? _a : []) {
                    if (typeof createStore !== 'string') {
                        const store = await createStore(database, oldVersion, transaction);
                        store.createIndex(TTL_INDEX_NAME, TTL_INDEX_KEY_PATH);
                        return;
                    }
                    if (database.objectStoreNames.contains(createStore)) {
                        // we return early here to avoid a store with the same name to be created
                        // on db version changes which would cause an error to be thrown
                        return;
                    }
                    const store = database.createObjectStore(createStore);
                    store.createIndex(TTL_INDEX_NAME, TTL_INDEX_KEY_PATH);
                }
                database.onversionchange = function () {
                    database.close();
                };
            },
            terminated() {
                onTerminated === null || onTerminated === void 0 ? void 0 : onTerminated();
            },
        });
        if ((stores === null || stores === void 0 ? void 0 : stores.default) && !idb.objectStoreNames.contains(stores === null || stores === void 0 ? void 0 : stores.default)) {
            throw new Error('Default store name not found');
        }
        const defaultStore = (_b = stores === null || stores === void 0 ? void 0 : stores.default) !== null && _b !== void 0 ? _b : idb.objectStoreNames[0];
        const storage = new Storage(idb, defaultStore);
        await storage.removeOutdatedRecords();
        return storage;
    }
    /**
     * Closes the open database connection after all active transactions are finalized.
     */
    async disconnect() {
        return this.idb.close();
    }
    /**
     * Removes the active indexed db storage.
     */
    async remove() {
        return deleteDB(this.idb.name);
    }
    /**
     * Gets the value for a given key from indexed db store, if the value has already expired
     * it's removed and returns undefined.
     *
     * @param key Key to fetch from the indexed db
     * @param storeName Optional store name, defaults to initial store
     */
    async get(key, opts) {
        var _a;
        const store = (_a = opts === null || opts === void 0 ? void 0 : opts.storeName) !== null && _a !== void 0 ? _a : this.defaultStore;
        const value = await this.idb.get(store, key);
        if ((value === null || value === void 0 ? void 0 : value.expireAt) && Date.now() >= value.expireAt) {
            await this.idb.delete(store, key);
            return;
        }
        return value === null || value === void 0 ? void 0 : value.body;
    }
    /**
     * Deletes the value for a given key from indexed db store if available.
     *
     * @param key Key to fetch from the indexed db
     * @param storeName Optional store name, defaults to initial store
     */
    async delete(key, opts) {
        var _a;
        const store = (_a = opts === null || opts === void 0 ? void 0 : opts.storeName) !== null && _a !== void 0 ? _a : this.defaultStore;
        await this.idb.delete(store, key);
    }
    /**
     * Gets all values from indexed db store, if the value has already expired
     * it's removed and returns undefined.
     *
     * @param storeName Optional store name, defaults to initial store
     */
    async getAll(opts) {
        var _a;
        const store = (_a = opts === null || opts === void 0 ? void 0 : opts.storeName) !== null && _a !== void 0 ? _a : this.defaultStore;
        await this.removeOutdatedRecords({ storeName: store });
        const values = await this.idb.getAll(store);
        return values.map((value) => value === null || value === void 0 ? void 0 : value.body);
    }
    /**
     * Sets the value for a given key to indexed db store, it wrapps the value with the given ttl to
     * expire the record. If TTL is not present, the value won't expire.
     *
     * @param key Key to set into the indexed db
     * @param value Value to be persisted
     * @param ttl Expire date for the value
     * @param storeName Optional store name, defaults to initial store
     * @returns
     */
    async put(key, value, opts) {
        var _a, _b;
        const store = (_a = opts === null || opts === void 0 ? void 0 : opts.storeName) !== null && _a !== void 0 ? _a : this.defaultStore;
        const expireAt = (_b = opts === null || opts === void 0 ? void 0 : opts.ttl) === null || _b === void 0 ? void 0 : _b.getTime();
        const storeValue = {
            expireAt: expireAt && expireAt > Date.now() ? expireAt : undefined,
            body: value,
        };
        return this.idb.put(store, storeValue, key);
    }
    /**
     * Removes all entries for the given store.
     *
     * @param storeName Optional store name, defaults to initial store
     */
    async clear(opts) {
        var _a;
        const store = (_a = opts === null || opts === void 0 ? void 0 : opts.storeName) !== null && _a !== void 0 ? _a : this.defaultStore;
        return this.idb.clear(store);
    }
    /**
     * Cleanup all outdated records of a given store
     */
    async removeOutdatedRecords(opts) {
        var _a;
        const store = (_a = opts === null || opts === void 0 ? void 0 : opts.storeName) !== null && _a !== void 0 ? _a : this.defaultStore;
        const entriesUntil = IDBKeyRange.upperBound(Date.now());
        const transaction = this.idb.transaction(store, 'readwrite');
        const expiredKeys = await transaction.db.getAllKeysFromIndex(store, TTL_INDEX_NAME, entriesUntil);
        const removeOperations = expiredKeys.map((expiredKey) => transaction.db.delete(store, expiredKey));
        await Promise.all([...removeOperations, transaction.done]);
    }
}
export { DB_NAME, DB_VERSION, DB_DEFAULT_STORE, Storage, };
