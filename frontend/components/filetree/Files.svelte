<!-- DownloadButton.svelte -->
<template>
  <button class="download-button" on:click={download}>Download</button>
</template>
<script>
  export let folder;
  export let download;

  function handleClick() {
    download(folder);
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