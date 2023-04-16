<!-- DownloadButton.svelte -->
<template>
    <Button size="small" kind="danger-tertiary" on:click={deleteFileTree}>Delete</Button>
</template>
<script>
  import { useCanister } from "@connect2ic/svelte";
  import { Button } from "carbon-components-svelte";
  import { localFileTrees } from "../../stores.js"

  export let folder;
  export let toogleInAction;
  export let reload;

  const [fileTreeRegistry] = useCanister("registry")
  
  async function deleteFileTree() {
    toogleInAction(true);
    console.log("DELETE");
    if (folder.fId && folder.fId.length > 0) {
      let ret = await $fileTreeRegistry.deleteFileTree(folder.fId[0]);
      console.log(ret);
    } else {
      console.log("File id not exist: " + folder.fId)
      // remove local
      $localFileTrees = [];
    }
    reload();
    toogleInAction(false);
  }

</script>
<style>
</style>