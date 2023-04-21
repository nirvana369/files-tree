# Decentralize FileTrees

The DApp supports managing and syncing a file tree from a local folder on your computer to the Internet Computer, a decentralized blockchain infrastructure. You can see a demo here: https://www.youtube.com/watch?v=UIYshKAJDVk or try a live demo as a user, or deploy one app for yourself as a developer. Please read the README.md file for instructions.

This version has several functions:

- Serving file data via HTTP
- Managing file trees/folders/files
- Syncing/deleting a local folder to the Internet Computer, syncing and downloading folders from the Internet Computer to the local machine
- Server info (scaling the backend canister when its wallet has more than 4 T cycles)
- Backend info (available memory)
- Profiler dashboard to monitor request calls by actor/action/function name and average processing time (to easily monitor and improve performance for fast UX and communication)
- You can serve file data by URL path: https://{canister_id}.ic0.app/principal (file owner)/file tree id/file hash?chunkId={0 to total chunk}.

Note that currently, this version stores file data in memory, so the client does not support uploading big file sizes. In the next version, I will support big file sizes and add features such as moving files, merging files, creating new files on the server, mailbox for user-received notifications when the file upload is done and progress of it, and more.

**Backend**

Canister written in Motoko
+   Registry canister : manage/store file-trees
+   File Storage canister : store file & chunks, auto scale 

**Frontend**

- Use Svelt template, display user's storage account, manage file-trees upload/download file, sync with local folder, delete file-trees


## Live Demo in IC Mainnet

https://www.youtube.com/watch?v=UIYshKAJDVk

https://iz4pk-pqaaa-aaaao-aikqq-cai.ic0.app/

![Screenshot](/frontend/assets/demo.png)

## Quick Start (Run locally)

Install:

- NodeJS 16.\* or higher https://nodejs.org/en/download/
- Internet Computer dfx CLI https://internetcomputer.org/docs/current/tutorials/deploy_sample_app/#dfx
- Visual Studio Code (Recommended Code Editor) https://code.visualstudio.com/Download
- VSCode extension - Motoko (Recommended) https://marketplace.visualstudio.com/items?itemName=dfinity-foundation.vscode-motoko

```bash
sh -ci "$(curl -fsSL https://internetcomputer.org/install.sh)"
```

Clone this Git repository:

```bash
git clone https://github.com/nirvana369/files-tree.git
```

Open command terminal:
Enter the commands to start dfx local server in background:

```bash
cd files-tree
dfx start --background
```

Note: If you run it in MacOS, you may be asked to allow connections from dfx local server.

Enter the commands to install dependencies, deploy canister and run client:

```bash
npm install
dfx deploy
npm run dev
```

Open in Chrome the following URL to try the demo app:  
http://localhost:3000/

Cleanup - stop dfx server running in background:

```bash
dfx stop
```

## Project Structure

Internet Computer has the concept of [Canister](https://internetcomputer.org/docs/current/concepts/canisters-code/) which is a computation unit. This project has 3 canisters:

- storage (backend)
- registry (backend)
- assets (frontend)

Updating : Log & monitor canister

Canister configurations are stored in dfx.json.

### Backend

Backend code is inside /canisters/ written in [Motoko language](https://internetcomputer.org/docs/current/motoko/main/motoko). Motoko is a type-safe language with modern language features like async/await and actor build-in. It also has [Orthogonal persistence](https://internetcomputer.org/docs/current/motoko/main/motoko/#orthogonal-persistence) which I find very interesting.


![Backend structure](/frontend/assets/backend-struct.png)

FileManager to manage & control a file-tree

Chunks of 1 file may be not store at the same canister, storage canister may communicate with others using the event bus - send event cross canister to perform some action like delete/update event asynchronously.

### Frontend

Frontend code - components structure :

![Frontend structure](/frontend/assets/frontend-struct.png)

Project use [carbon-components-svelte](https://carbon-components-svelte.onrender.com/) framework.

## Backend dev

You can deploy it to the local DFX server using:

```bash
dfx deploy
```

## Deploy to IC Network Canister

The most exciting part is to deploy your Next.js / Internet Computer Dapp to production Internet Computer mainnet blockchain network.

To do that you will need:

- ICP tokens and convert it to [cycles](https://internetcomputer.org/docs/current/concepts/tokens-cycles/)
- Cycles wallet

Follow the [Create a new cycles wallet](https://internetcomputer.org/docs/current/developer-docs/setup/cycles/cycles-wallet/#create-a-new-cycles-wallet) guide to create a wallet.  

Deploy command :

```bash
dfx deploy --network ic --argument '(vec{principal "ncgt3-jaaaa-aaaao-aikpq-cai"}, vec {principal "i65j6-ciaaa-aaaao-aikqa-cai"})'
```
When you deploy with argument, this params use when deploy storage canister, params is 2 principal arrays, the 1st params is admin list, 2nd is storage list.

Or you can pass 2 empty arrays, then add admin or storage later by call funtions supported in registry canister, after you call function to add admin/storage,
registry canister will notify all storages to update admin/storage list :
```bash
dfx deploy --network ic --argument '(vec{}, vec {})'

dfx canister call registry addAdmin --network ic '(principal "ncgt3-jaaaa-aaaao-aikpq-cai")'
dfx canister call registry addStorage --network ic '(principal "i65j6-ciaaa-aaaao-aikqa-cai")'

```

Open Chrome and go to https://[canisterId].raw.ic0.app/  
Replace [canisterId] by the canister id in the IC network (canister id will be config in ./canister_ids.json). Or you can find it by running:

```bash
dfx canister --network ic id storage
dfx canister --network ic id registry
dfx canister --network ic id assets
```

==============================================================

# Project use Svelte Internet Computer Starter Template
# Github
https://github.com/MioQuispe/create-ic-app