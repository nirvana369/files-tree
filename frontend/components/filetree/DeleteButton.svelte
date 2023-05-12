<!-- DownloadButton.svelte -->
<template>
    <Button size="small" kind="danger-tertiary" on:click={deleteFileTree}>Delete</Button>
</template>
<script>
  import { useCanister } from "@connect2ic/svelte";
  import { Button } from "carbon-components-svelte";
  import { localFileTrees, filesData } from "../../stores.js"
  import { getIsFolder, logging } from "../../utils"

  export let folder;
  export let toogleInAction;
  export let reload;

  const [fileTreeRegistry] = useCanister("registry")
  
  async function deleteFileTree() {
    toogleInAction(true);
    logging("DELETE");
    // remove local
    await recursive(folder, async function syncCallback(file) {
        $filesData[file.hash] = null;
    });

    if (folder.id > 0) {
      let ret = await $fileTreeRegistry.deleteFileTree(folder.id);
      logging(ret);
    } else {
      logging("File id not exist: " + folder.id)
      // remove local
      $localFileTrees = [];
    }
    reload(folder.id, folder.name);
    toogleInAction(false);
  }

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
</style>