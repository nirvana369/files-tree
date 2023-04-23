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
          traverseDirectory,
          mergeUInt8Arrays,
          } from "../../utils";
  import { syncFiles, filesData, user } from "../../stores.js"
  import { useConnect } from "@connect2ic/svelte"
  import md5 from 'md5';
  import { Grid, Row, Column, InlineLoading } from "carbon-components-svelte";
  import { streamContent } from "../../streaming/candid_streaming";
  import { concat, HttpAgent } from '@dfinity/agent';

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
  export let reload;

  const [fileTreeRegistry] = useCanister("registry")
 
  let fileTreeSelected;
  

  async function selectFolder() {
    let fileTree = null;
    try {
        directoryHandle = await window.showDirectoryPicker({ writable: true });
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

    const fileTree = await traverseDirectory(directoryHandle, function(name, hash, content) {
        const file = { name: name, content: content };
        console.log("your file is : " + name);
        console.log(file);
        $filesData[hash] = content;
        // save file to localDB ?
      });
      console.log($filesData);
      let tmp = await $fileTreeRegistry.verifyFileTree(fileTree);
      console.log("verify done");
      return fileTree;
  }

  async function handleSync() {
    toogleInAction(true);
    toogleEnableDownload(false, folder);
    $syncFiles = [];
    try {
      let syncFoler = await sync();
      if (syncFoler != null) {
        toogleEnableDownload(true, syncFoler);
      }
    } catch (e) {
      console.log(e);
    }
    //   reload();  
    toogleInAction(false);
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
      console.log("FILE MAP");
      console.log($filesData);
      console.log("MERGE FILE TREE");
      console.log("--FOLDER");
      console.log(folder);
      console.log("--FOLDER SELECTED");
      console.log(fileTreeSelected);

      if (!folder || !folder.id || folder.id.length === 0) {
          // new selected folder -> register & upload file
          let ret = await $fileTreeRegistry.createFileTree(fileTreeSelected);
          console.log("CREATE FILE TREE");
          console.log(ret);
          if (ret.ok) {
            // folder has struct similar to ret.ok, diffirent is ret.ok not have attribute data
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
          // folder has struct similar to ret.ok, diffirent is ret.ok not have attribute data
          folder = ret.ok;
        } else {
          console.log(ret.err);
          return;
        }
      }
      console.log("RECURSIVE SYNC");

      await recursive(folder, async function syncCallback(file) {
        if (file.state.hasOwnProperty('empty')) {
            await syncUp(folder.id, file);
        } else if (file.state.hasOwnProperty('ready')) {
            // await syncDown(folder.id, file);
            await streamDown(folder.id, file);
        }
      });
      toogleModal(false);
      console.log("READY TO DOWNLOAD");
      console.log(folder);
      return folder;
  }

  async function syncUp(fileTreeId, file) {
    const data = $filesData[file.hash];
    console.log(data);
    if (!data) {
      // if file data not exist to sync up ? remove file ?
      $syncFiles = [...$syncFiles, file.name + " - FILE NOT FOUND IN SELECTED FOLDER!"];
      alert("File data not found! re-select folder | name: " + file.name + " | hash: " + file.hash);
      return;
    }
    const chunkLength = 1000000;
    let totalChunk = Math.ceil(data.length / chunkLength);
    let chunkId = 0;
    let start = 0;

    let err = 0;
    let startTime = new Date().getTime();
    while (chunkId < totalChunk) {
      start = chunkId * chunkLength;
      const c = data.slice(start, start + chunkLength);
      console.log("PROC CHUNK: " + chunkId + " | size: " + c.length);
      let bytes = Array.from(c);
      let chunk = {
          fileId : file.id,
          chunkOrderId : chunkId,
          data : bytes,
      }
      let syncRet; 
      try {
        syncRet = await $fileTreeRegistry.streamUpFile(fileTreeId, file.id, chunk);
      } catch (error) {
        syncRet.err = error;
      }
      console.log(file.id + " | stream up | " + chunkId);
      console.log(chunk);
      if (syncRet.ok) {
        chunkId++;
        err = 0;
        // file.state = syncRet.ok;
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

    if (err > 0) {
      // if file data not exist to sync up ? remove file ?
      $syncFiles = [...$syncFiles, file.name + " - FILE SYNC UP FAILED!"];
    } else {
      $syncFiles = [...$syncFiles, file.name];
      file.state = {ready : null};
      reload(file);
    }
    
    const processTime = new Date().getTime() - startTime;
    console.log("UPLOAD TIME : " + processTime + " | file : " + file.name);
  }

  async function syncDown(fileTreeId, file) {

    const localFileData = $filesData[file.hash];
    if (localFileData != null) {
      file.data = localFileData;
      $syncFiles = [...$syncFiles, file.name];
      return;
    };

    let totalChunk = file.totalChunk;
    let i = 0;
    let err = 0;
    var chunkData = new Uint8Array();
    let startTime = new Date().getTime();
    while (i < totalChunk) {
        let syncRet;
        try {
          syncRet = await $fileTreeRegistry.streamDownFile(fileTreeId, file.id, i);
        } catch (error) {
          syncRet.err = error;
        }
        console.log(syncRet);
        if (syncRet.ok) {
          let chunk = syncRet.ok;
          chunkData = mergeUInt8Arrays(chunkData, chunk.data);
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
    if (err > 0) {
      // if file data not exist to sync up ? remove file ?
      $syncFiles = [...$syncFiles, file.name + " - FILE SYNC DOWN FAILED!"];
    } else {
      $filesData[file.hash] = chunkData;
      $syncFiles = [...$syncFiles, file.name];
    }

    console.log(file.name + " - " + chunkData.length);

    var nat8Arr = Array.from(chunkData)    // Uint8Array -> [Nat8]
    let hash = md5(nat8Arr);
    console.log("hash cmp: hash1: " + file.hash + " | hash2:" + hash);
    const processTime = new Date().getTime() - startTime;
    console.log("DOWNLOAD TIME : " + processTime + " | file : " + file.name);
  }

  export var HTTPHeaders;
  (function (HTTPHeaders) {
      HTTPHeaders["Vary"] = "vary";
      HTTPHeaders["CacheControl"] = "cache-control";
      HTTPHeaders["Range"] = "range";
      HTTPHeaders["ContentEncoding"] = "content-encoding";
  })(HTTPHeaders || (HTTPHeaders = {}));

  var __rest = (this && this.__rest) || function (s, e) {
      var t = {};
      for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
          t[p] = s[p];
      if (s != null && typeof Object.getOwnPropertySymbols === "function")
          for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
              if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                  t[p[i]] = s[p[i]];
          }
      return t;
  };
  export class NotAllowedRequestRedirectError extends Error {
      constructor() {
          super('Due to security reasons redirects are blocked on the IC until further notice!');
          Object.setPrototypeOf(this, new.target.prototype);
      }
  }


  async function streamDown(fileTreeId, file) {
    let startTime = new Date().getTime();
    const agent = new HttpAgent({
      host: "https://ic0.app",
    });

    let url = 'https://' + process.env.REGISTRY_CANISTER_ID + '.ic0.app/' + $user + '/' + fileTreeId + '/' + file.hash;
    const requestUrl = new URL(url);
    const requestHeaders = [['Host', requestUrl.hostname]];
    requestHeaders.push(['Accept-Encoding', 'gzip, deflate, identity']);
    let httpRequest = {
        method : "GET",
        url : url,
        headers: requestHeaders,
        body: new Uint8Array([0]),
        certificate_version: [],
    };
    console.log(url);
    
    console.log(httpRequest);
    let httpResponse = await $fileTreeRegistry.http_request(httpRequest);

    const upgradeCall = httpResponse.upgrade.length === 1 && httpResponse.upgrade[0];
    let _a, _b;
    const bodyEncoding = (_b = (_a = httpResponse.headers
        .filter(([key]) => key.toLowerCase() === HTTPHeaders.ContentEncoding)) === null || _a === void 0 ? void 0 : _a.map((header) => header[1].trim()).pop()) !== null && _b !== void 0 ? _b : '';
    if (upgradeCall) {
        const { certificate_version } = httpRequest, httpUpdateRequest = __rest(httpRequest, ["certificate_version"]);
        // repeat the request as an update call
        httpResponse = await $fileTreeRegistry.http_request_update(httpUpdateRequest);
    }
    // Redirects are blocked for query calls only: if this response has the upgrade to update call flag set,
    // the update call is allowed to redirect. This is safe because the response (including the headers) will go through consensus.
    if (!upgradeCall &&
        httpResponse.status_code >= 300 &&
        httpResponse.status_code < 400) {
        throw new NotAllowedRequestRedirectError();
    }
    console.log(httpResponse);
    // if we do streaming, body contains the first chunk
    let buffer = new ArrayBuffer(0);
    buffer = concat(buffer, httpResponse.body);
    console.log("BUFFER");
    console.log(buffer);
    if (httpResponse.streaming_strategy.length !== 0) {
        buffer = concat(buffer, await streamContent(agent, process.env.REGISTRY_CANISTER_ID, httpResponse.streaming_strategy[0]));
    }
    const chunkData = new Uint8Array(buffer);

    console.log(file.name + " - " + chunkData.length);

    var nat8Arr = Array.from(chunkData)    // Uint8Array -> [Nat8]
    let hash = md5(nat8Arr);
    if (file.hash != hash) {
      // if file data not exist to sync up ? remove file ?
      $syncFiles = [...$syncFiles, file.name + " - FILE CHECKSUM IS WRONG!"];
    } else {
      $filesData[file.hash] = chunkData;
      $syncFiles = [...$syncFiles, file.name];
    }
    console.log("hash cmp: hash1: " + file.hash + " | hash2:" + hash);
    const processTime = new Date().getTime() - startTime;
    console.log("DOWNLOAD TIME : " + processTime + " | file : " + file.name);
  };
  
  async function recursive(fileTree, callback) {
      if (getIsFolder(fileTree.fType)) {
          for (const child of fileTree.children) {
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