<!-- DownloadButton.svelte -->
<template>
    <Grid fullWidth >
      <Row>
          <Column sm={1} md={1} lg={3}>
              <Button size="small" kind="tertiary" on:click={handleSync}>Sync</Button>
          </Column>
          <Column sm={1} md={1} lg={3}>
            {#if promise != null}
              {#await promise}
                <InlineLoading />
              {:then f}
                <DownloadButton folder={f} />
              {:catch error}
                <p style="color: red">{error.message}</p>
              {/await}
            {/if}
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

  const [fileTreeRegistry] = useCanister("registry")
 
  let fileTreeSelected;

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

  let promise = null;

  function handleSync() {
    $syncFiles = [];
    promise = sync();
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
      let fileMap = getFileTreeData(fileTreeSelected);
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
      
      
      console.log("MERGE RESULT");
      let x = mergeFileTree(folder, fileTreeSelected);
      console.log(x);
      
      let fileTreeId = folder.fId[0];
      await recursiveSync(fileTreeId, fileMap, x);
      console.log(x);

      toogleModal(false);
      
      return x;
  }

  async function recursiveSync(fileTreeId, fileMap, fileTree) {
      if (getIsFolder(fileTree.fType)) {
          for (const child of fileTree.children[0]) {
              await recursiveSync(fileTreeId, fileMap, child);
          }
      } else {
          const canisterId = fileTree.fCanister[0];
          const fId = fileTree.fId[0];
          const f = fileMap[fileTree.fHash[0]];
          console.log("======================");
          console.log(canisterId);
          console.log(fId);
          console.log(f);
          console.log(fileTree);
          console.log($principal);
          console.log("======================");
          console.log(fileTree.fState.hasOwnProperty('ready'));
          if (fileTree.fState.hasOwnProperty('empty')) {

                if (!f || !f.fData) {
                  $syncFiles = [...$syncFiles, fileTree.fName + " - FILE NOT FOUND IN SELECTED FOLDER!"];
                  // alert("File data not found! re-select folder | name: " + fileTree.fName + " | hash: " + fileTree.fHash[0]);
                  return;
                }
                const chunkLength = 1000000;
                let totalChunk = Math.ceil(f.fData[0].length / chunkLength);
                let chunkId = 0;
                let start = 0;

                await $fileTreeRegistry.removeChunksCache(canisterId, fId);
                let err = 0;
                while (chunkId < totalChunk) {
                  start = chunkId * chunkLength;
                  const c = f.fData[0].slice(start, start + chunkLength);
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
                $syncFiles = [...$syncFiles, fileTree.fName];
          } else if (fileTree.fState.hasOwnProperty('ready')) {
                const localFile = fileMap[fileTree.fHash[0]];
                if (localFile && localFile.fHash[0] == fileTree.fHash[0] && localFile.fData && localFile.fData.length > 0) {
                  fileTree.fData = localFile.fData;
                  $syncFiles = [...$syncFiles, fileTree.fName];
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
                  fileTree.fData = [chunkData];
                  fileMap[fileTree.fHash[0]] = fileTree;
                  $syncFiles = [...$syncFiles, fileTree.fName];
                }
                
                console.log(fileTree.fName + " - " + fileTree.fData[0].length);

                var nat8Arr = Array.from(chunkData)    // Uint8Array -> [Nat8]
                let hash = md5(nat8Arr);
                console.log("hash cmp: hash1: " + fileTree.fHash[0] + " | hash2:" + hash);
          }
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