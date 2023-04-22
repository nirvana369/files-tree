<!-- DownloadButton.svelte -->
<template>
    <Button size="small" kind="tertiary" on:click={download}>Download</Button>
</template>
<script>
  import { Button } from "carbon-components-svelte";
  import {getIsFolder} from "../../utils";
  import { filesData } from "../../stores"

  export let folder;
  export let toogleInAction;

  async function download() {
    toogleInAction(true);
    console.log("PREPARE DOWNLOAD");
    console.log(folder);
    try {
      const dirHandle = await window.showDirectoryPicker();
      await createDirectory(dirHandle, folder);
    } catch (error) {
      console.error("Failed to select folder:", error);
    }
    toogleInAction(false);
  }

  async function createFile(fileHandle, content, contentType) {
    // convert [uint8] -> ArrayBuffer -> Blob
    let blob;
    if (contentType !== "") {
        blob = new Blob([new Uint8Array(content).buffer], {type: contentType});
    } else {
        blob = new Blob([new Uint8Array(content).buffer]);
    }
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
    const curDir = await dirEntry.getDirectoryHandle(fileTree.name, { create: true });
    for (const child of fileTree.children) {
        if (getIsFolder(child.fType)) {
           createDirectory(curDir, child);
        } else {
          const data = $filesData[child.hash];
          if (data && data.length > 0) {
            let curFile = await curDir.getFileHandle(child.name, { create: true });
            createFile(curFile, data, child.fType.file);
          } else {
            alert("You need sync first!");
          }
        }
      }
  }

</script>
<style>
  /* .download-button {
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
  } */
</style>