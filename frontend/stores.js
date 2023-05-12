import { writable } from 'svelte/store'

export const view = writable({
    home: 1,
    view: 2,
    create: 3,
    vote: 4,
    current: 1,
});

export const proposaltoVote = writable({
    proposalID: "null"
});

export const hasvoted = writable(false);

export const user = writable(null);
export const daoActor = writable(null);
export const ledgerActor = writable(null);
export const neuron = writable(null);
export const serverFileTrees = writable([]);
export const localFileTrees = writable([]);
export const syncFiles = writable([]);
export const filesData = writable({});
export const isDebug = writable(false);