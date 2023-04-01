<!-- FilesTree.svelte -->
<template>
  <div class="file" class:folder={isFolder} class:open={isOpen}>
    <div class="name" on:click={toggleOpen}>
      {isFolder ? (!isOpen ? '📁' : '📂') : '📜'}
      {file.name}
    </div>
    {#if isFolder && isOpen}
      <div class="children">
        {#each file.children as child}
          <FilesTree file={child} />
        {/each}
      </div>
    {/if}
  </div>
</template>

<script>
  import FilesTree from "./FilesTree.svelte"
  export let file;

  let isOpen = false;

  function toggleOpen() {
    isOpen = !isOpen;
  }

  function getIsFolder() {
    return file.children && file.children.length > 0;
  }

  $: isFolder = getIsFolder();
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
