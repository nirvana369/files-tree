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
        <a href={'http://ryjl3-tyaaa-aaaaa-aaaba-cai.localhost:8000/' + $user + '/' + rootId + '/' + file.hash} target="_blank">{file.name}</a>
        {isSync ?  '✅' : '❌'}
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

  export let file;
  export let rootId;

  let isOpen = true;

  function toggleOpen() {
    isOpen = !isOpen;
  }

  function openUrl() {
    window.open('http://ryjl3-tyaaa-aaaaa-aaaba-cai.localhost:8000/' + $user + '/' + rootId + '/' + file.hash, '_blank').focus();
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
