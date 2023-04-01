<!-- DownloadButton.svelte -->
<template>
  {#if folder.fId || folder.fId.length === 0 }
    <button class="sync-button" on:click={sync}>Sync</button>
  {:else}
    <button class="download-button" on:click={download}>Download</button>
  {/if}
</template>
<script>
  import { useCanister } from "@connect2ic/svelte";
  import {convert2CandidFileTree} from "../../utils";

  export let folder;

  const [fileRegistry, { loading }] = useCanister("registry")

  async function sync() {
      let x = convert2CandidFileTree(folder);
      let ret = await $fileRegistry.registerFileTree(x);
      console.log(ret);
  }

  async function download() {
    const dirHandle = await window.showDirectoryPicker();
    await createDirectory(dirHandle, folder);
  }

  async function createFile(fileHandle, content) {
    // convert [uint8] -> ArrayBuffer -> Blob
    let blob = new Blob([new Uint8Array(content[0]).buffer]);
    /**
     * Secure context : fileHandle.createWritable()
     * This feature is available only in secure contexts (HTTPS), in some or all supporting browsers.
     */
    const writable = await fileHandle.createWritable();
    // Write the contents of the file to the stream.
    await writable.write(blob);
    // Close the file and write the contents to disk.
    await writable.close();
  }

  async function createDirectory(dirEntry, fileTree) {
    const name = fileTree.name;
    const curDir = await dirEntry.getDirectoryHandle(name, { create: true });
    for (const child of fileTree.children) {
        if (child.kind === "directory") {
           createDirectory(curDir, child);
        } else {
          const fileName = child.name;
          let curFile = await curDir.getFileHandle(fileName, { create: true });
          createFile(curFile, child.fData);
        }
      }
  }

</script>
<style>
  .download-button {
    padding: 0.5rem 1rem;
    background-color: #4CAF50;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s ease-in-out;
  }
  .download-button:hover {
    background-color: #3E8E41;
  }
</style>