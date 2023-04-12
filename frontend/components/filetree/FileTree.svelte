<!-- FilesTree.svelte -->
<template>
  <div class="file" class:folder={isFolder} class:open={isOpen}>
    <div class="name" on:click={toggleOpen}>
      {isFolder ? (!isOpen ? '📁' : '📂') : '📜'}
      {file.fName}
    </div>
    {#if isFolder && isOpen}
      <div class="children">
        {#each file.children[0] as child}
          <FileTree file={child} />
        {/each}
      </div>
    {/if}
  </div>
</template>

<script>
  import {getIsFolder} from "../../utils";
  import FileTree from "./FileTree.svelte";

  export let file;

  let isOpen = false;

  function toggleOpen() {
    isOpen = !isOpen;
  }

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
