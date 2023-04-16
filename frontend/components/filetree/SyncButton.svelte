<!-- DownloadButton.svelte -->
<template>
    <Grid fullWidth >
      <Row>
          <Column sm={1} md={1} lg={3}>
              <Button size="small" kind="tertiary" on:click={handleSync}>Sync</Button>
          </Column>
      </Row>
    </Grid>
</template>
<script>
  import { Button } from "carbon-components-svelte";
  import { useCanister } from "@connect2ic/svelte";
  import {mergeFileTree,
          getIsFolder, 
          getFileTreeData, 
          traverseDirectory,
          mergeUInt8Arrays} from "../../utils";
  import { localFileTrees, syncFiles } from "../../stores.js"
  import { Principal } from "@dfinity/principal"
  import { useConnect } from "@connect2ic/svelte"
  import md5 from 'md5';
  import { Grid, Row, Column, InlineLoading } from "carbon-components-svelte";
  import DownloadButton from "./DownloadButton.svelte";

  const { principal } = useConnect({
    onConnect: () => {
      // Signed in
    },
    onDisconnect: () => {
      // Signed out
    }
  })
  export let folder;
  export let directoryHandle;
  export let toogleModal;
  export let toogleInAction;
  export let toogleEnableDownload;

  const [fileTreeRegistry] = useCanister("registry")
 
  let fileTreeSelected;
  let fileMap = {};

  async function selectFolder() {
    let fileTree = null;
    try {
        directoryHandle = await window.showDirectoryPicker();
        fileTree = await checkFileTree();
        // document.getElementById("store-button").disabled = false;
      } catch (error) {
        console.error("Failed to select folder:", error);
      }
      return fileTree;
  }

  async function checkFileTree() {
    if (!directoryHandle) {
      alert("Please select a folder.");
      return null;
    }

    const fileTree = await traverseDirectory(directoryHandle, function(name, content) {
        const file = { name: name, content: content };
        console.log("your file is : " + name);
        console.log(file);
        // save file to localDB ?
      });
      let tmp = await $fileTreeRegistry.verifyFileTree(fileTree);
      // after verify if data changing -> update fileTree
      // $localFileTrees = [...$localFileTrees, fileTree];
      console.log("verify done");
      return fileTree;
  }

  async function handleSync() {
    toogleInAction(true);
    toogleEnableDownload(false, folder);
    $syncFiles = [];
    let syncFoler = await sync();
    if (syncFoler != null) {
      toogleEnableDownload(true, syncFoler);
    }
    toogleInAction(false);
  }

  function updateFileMap(listFile) {
    let ret = {};
    for (const f of listFile) {
      fileMap[f.fHash[0]] = f.fData;
    }
  }

  async function sync() {
      if (!directoryHandle) {
        fileTreeSelected = await selectFolder();
      } else {
        fileTreeSelected = await checkFileTree();
      }
      if (!directoryHandle) {
        return null;
      }
      toogleModal(true);

      console.log("SELECT FOLDER");
      console.log(directoryHandle);
      updateFileMap(getFileTreeData(fileTreeSelected));
      console.log("FILE MAP");
      console.log(fileMap);
      console.log("MERGE FILE TREE");
      console.log("--FOLDER");
      console.log(folder);
      console.log("--FOLDER SELECTED");
      console.log(fileTreeSelected);

      if (!folder || !folder.fId || folder.fId.length === 0) {
          // new selected folder -> register & upload file
          let ret = await $fileTreeRegistry.createFileTree(fileTreeSelected);
          console.log("CREATE FILE TREE");
          console.log(ret);
          if (ret.ok) {
            // folder has struct similar to ret.ok, diffirent is ret.ok not have attribute fData
            folder = ret.ok;
          } else {
            console.log(ret.err);
            return;
          }
      } else {
        // check & update file tree
        let merge = mergeFileTree(folder, fileTreeSelected);
        console.log("MERGE RESULT");
        console.log(merge);
        let ret = await $fileTreeRegistry.updateFileTree(merge);
        console.log("UPDATE FILE TREE");
        console.log(ret);
        if (ret.ok) {
          // folder has struct similar to ret.ok, diffirent is ret.ok not have attribute fData
          folder = ret.ok;
        } else {
          console.log(ret.err);
          return;
        }
      }
      console.log("RECURSIVE SYNC");
      let fileTreeId = folder.fId[0];

      await recursive(folder, async function syncCallback(file) {
        if (file.fState.hasOwnProperty('empty')) {
            await syncUp(fileTreeId, file);
        } else if (file.fState.hasOwnProperty('ready')) {
            await syncDown(file);
        }
      });
      toogleModal(false);
      console.log("READY TO DOWNLOAD");
      console.log(folder);
      return folder;
  }

  async function syncUp(fileTreeId, file) {
    const canisterId = file.fCanister[0];
    const fId = file.fId[0];
    const fData = fileMap[file.fHash[0]];
    if (!fData) {
      // if file data not exist to sync up ? remove file ?
      $syncFiles = [...$syncFiles, file.fName + " - FILE NOT FOUND IN SELECTED FOLDER!"];
      // alert("File data not found! re-select folder | name: " + file.fName + " | hash: " + file.fHash[0]);
      return;
    }
    const chunkLength = 1000000;
    let totalChunk = Math.ceil(fData[0].length / chunkLength);
    let chunkId = 0;
    let start = 0;

    await $fileTreeRegistry.removeChunksCache(canisterId, fId);
    let err = 0;
    while (chunkId < totalChunk) {
      start = chunkId * chunkLength;
      const c = fData[0].slice(start, start + chunkLength);
      console.log("PROC CHUNK: " + chunkId + " | size: " + c.length);
      let bytes = Array.from(c);
      let chunk = {
          fId : Number(fId),
          fChunkId : chunkId,
          fTotalChunk : totalChunk,
          fData : bytes,
          fOwner : Principal.fromText($principal)
      }
      let syncRet = await $fileTreeRegistry.streamUpFile(fileTreeId, canisterId, chunk);
      console.log(fId + " | stream up | " + chunkId);
      console.log(chunk);
      if (syncRet.ok) {
        chunkId++;
        err = 0;
        // fileTree.fState = syncRet.ok;
        console.log(syncRet);
      } else {
        err++;
        console.log(syncRet);
      }
      if (err == 3) {
        alert("Server connection error!");
        break;
      }
    }
    $syncFiles = [...$syncFiles, file.fName];
  }

  async function syncDown(file) {
    const canisterId = file.fCanister[0];
    const fId = file.fId[0];
    const localFileData = fileMap[file.fHash[0]];
    if (localFileData && localFileData.length > 0) {
      // if file already download at local
      file.fData = localFileData;
      $syncFiles = [...$syncFiles, file.fName];
      return;
    }
    let totalChunk = 1;
    let i = 0;
    let err = 0;
    var chunkData = new Uint8Array();
    while (i < totalChunk) {
        let syncRet = await $fileTreeRegistry.streamDownFile(canisterId, fId, i);
        console.log(syncRet);
        if (syncRet.ok) {
          let chunk = syncRet.ok;
          chunkData = mergeUInt8Arrays(chunkData, chunk.fData);
          totalChunk = chunk.fTotalChunk;
          i++;
          err = 0;
        } else {
          err++;
          if (err == 3) {
            // if retry 3 times
            break;
          }
          if (syncRet.err == "File data is #empty") {
            alert(syncRet.err);
            break;
          }
        }
        
    }
    if (err == 0) {
      file.fData = [chunkData];
      fileMap[file.fHash[0]] = [chunkData];
      $syncFiles = [...$syncFiles, file.fName];
    }
    
    console.log(file.fName + " - " + file.fData[0].length);

    var nat8Arr = Array.from(chunkData)    // Uint8Array -> [Nat8]
    let hash = md5(nat8Arr);
    console.log("hash cmp: hash1: " + file.fHash[0] + " | hash2:" + hash);
  }

  async function recursive(fileTree, callback) {
      if (getIsFolder(fileTree.fType)) {
          for (const child of fileTree.children[0]) {
              await recursive(child, callback);
          }
      } else {
          await callback(fileTree);
      }
  }

</script>
<style>
  /* .sync-button {
    padding: 0.5rem 1rem;
    width: 100px;
    background-color: #4CAF50;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s ease-in-out;
  }
  .sync-button:hover {
    background-color: #3E8E41;
  } */
</style>