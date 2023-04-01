<script>
  import logo from "../assets/dfinity.svg"
  import TreeExplorer from "./filetree/TreeExplorer.svelte";
  import { onMount } from 'svelte';
  import { useCanister } from "@connect2ic/svelte";
  import md5 from 'md5';
  import { listFolders } from "../stores.js"
  import {convert2CandidFileTree} from "../utils";

  const [fileRegistry, { loading }] = useCanister("registry")
  let directoryHandle;
  let folders = [];

  async function selectFolder() {
    try {
        directoryHandle = await window.showDirectoryPicker();
        await checkFileTree();
        // document.getElementById("store-button").disabled = false;
      } catch (error) {
        console.error("Failed to select folder:", error);
      }
  }

  async function checkFileTree() {
    if (!directoryHandle) {
      alert("Please select a folder.");
      return;
    }

    let fileTree = await traverseDirectory(directoryHandle, function(name, content) {
        const file = { name: name, content: content };
        console.log(file);
        // save file to localDB ?
      });
      // let r = await objectStore.add(fileTree);
      let x = convert2CandidFileTree(fileTree);
      let tmp = await $fileRegistry.verifyFileTree(x);
      // after verify if data changing -> update fileTree
      folders = [...folders, fileTree];
      console.log(tmp);
  }

  async function traverseDirectory(dirHandle, callback) {
      let entries = await dirHandle.entries();
      let entry = await entries.next();
      let ret = {
            name : dirHandle.name,
            kind : dirHandle.kind,
            fId : [],
            fName : dirHandle.name,
            fType : {directory : null},
            fCanister : [],
            fHash : [],
            fData : [],
            children : []
          }; 
      while (entry.value) {
        let obj = entry.value[1];
        if (obj.kind == "directory") {
          let sub = await traverseDirectory(obj, callback);
          ret.children.push(sub);
        } else if (obj.kind == "file") {
          const fileHandle = await obj.getFile();
          const file = await fileHandle.arrayBuffer();
          // callback(obj.name, file);
          var ia = new Uint8Array(file);  // ArrayBuffer -> Uint8Array
          var nat8Arr = [Array.from(ia)]    // Uint8Array -> [Nat8]
          let hash = md5(Array.from(ia));
          // console.log(new Uint8Array(nat8Arr[0]).buffer);  // convert [Nat8] -> to file
          let f = {
            name : obj.name,
            kind : obj.kind,
            fId : [],
            fName : obj.name,
            fType : {file : null},
            fCanister : [],
            fHash : [hash],
            fData : nat8Arr,
            children : []
          };
          ret.children.push(f);
        }
        
        entry = await entries.next();
      }
      return ret;
    }

  onMount(() => {
    // code to fetch tree data from server
    console.log("hello");
  });
</script>

<div class="container">
  <div class="header">
    <div class="logo">
      <img src={logo} alt="DFiles logo">
      <span>DFiles</span>
    </div>
    <div class="navigation">
      <button class="select-button" on:click={() => selectFolder()}>Select folder</button>
      <!-- <button id="store-button" class="upload-button" on:click={() => upload()}>Upload</button> -->
    </div>
  </div>
  {#each folders as f}
      <TreeExplorer folder={f}/>
  {/each}
</div>


<style>
  .header {
    grid-column: 1 / -1;
    display: flex;
    justify-content: space-between;
    align-items: center;
    background-color: #333;
    color: white;
    padding: 0.5rem;
  }
</style>