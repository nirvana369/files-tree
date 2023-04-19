<!-- FilesTree.svelte -->
<template>
  <div class="file" class:folder={isFolder} class:open={isOpen}>
    {#if isFolder}
      <div class="name" on:click={toggleOpen}>
        {!isOpen ? '📁' : '📂'}
        {file.name}
      </div>
    {:else}
      <!-- <div class="name" on:click={openUrl}> -->
        {'📜'}
        {#if isSync}
          <a href={url + $user + '/' + rootId + '/' + file.hash} target="_blank">{file.name}</a>
          {'✅'}
        {:else}
          {file.name}
          {'❌'}
        {/if}
      <!-- </div> -->
    {/if}
    {#if isFolder && isOpen}
      <div class="children">
        {#each file.children as child}
          <FileTree file={child} rootId={rootId} />
        {/each}
      </div>
    {/if}
  </div>
</template>

<script>
  import {getIsFolder} from "../../utils";
  import FileTree from "./FileTree.svelte";
  import { user } from "../../stores";
  import { useCanister } from "@connect2ic/svelte";
  
  export let file;
  export let rootId;
  
  const [fileTreeRegistry] = useCanister("registry")
  let isOpen = true;
  const url = getServerUrl();

  function toggleOpen() {
    isOpen = !isOpen;
  }

  function getServerUrl() {
    // if (process.env.NODE_ENV !== "ic") {
    //   return 'http://' + process.env.REGISTRY_CANISTER_ID + '.localhost:8000/';
    // } else {
      return 'https://' + process.env.REGISTRY_CANISTER_ID + '.ic0.app/';
    // }
  }
  function getIsSync() {
    if (file.fType && file.fType.hasOwnProperty('directory')) {
      return false;
    }
    return (file.state && file.state.hasOwnProperty('ready'));
    // return file.children && file.children.length > 0;
  }

  $: isSync = getIsSync();
  $: isFolder = getIsFolder(file.fType);


</script>

<style>
  .file {
    display: flex;
    align-items: center;
    padding: 0.5rem;
    border-bottom: 1px solid #eee;
    cursor: pointer;
  }

  .file:last-child {
    border-bottom: none;
  }

  .folder {
    font-weight: bold;
  }

  .name {
    flex: 1;
  }

  .open .name {
    font-weight: bold;
  }

  .children {
    margin-left: 1rem;
  }
</style>
