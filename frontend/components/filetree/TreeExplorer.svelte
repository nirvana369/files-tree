<!-- TreeExplorer.svelte -->
<template>
  <div class="container">
    <h2>{title}</h2>
    <div class="files-container">
      <FilesTree file={folder} />
    </div>
    <div class="download-container">
      <DownloadButton {folder} />
    </div>
  </div>
</template>

<script>
  import FilesTree from './FilesTree.svelte';
  import DownloadButton from './DownloadButton.svelte';

  export let title = '';
  export let folder;

  function getFolder() {
    return folder || getDefaultFolder();
  }

  function getDefaultFolder() {
    return {
      name: 'root',
      children: [
        {
          name: 'folder1',
          children: [
            {
              name: 'file1-1.js',
              content: 'console.log("Hello from file1-1.js!");'
            },
            {
              name: 'file1-2.js',
              content: 'console.log("Hello from file1-2.js!");'
            }
          ]
        },
        {
          name: 'folder2',
          children: [
            {
              name: 'file2-1.js',
              content: 'console.log("Hello from file2-1.js!");'
            },
            {
              name: 'file2-2.js',
              content: 'console.log("Hello from file2-2.js!");'
            }
          ]
        },
        {
          name: 'file3.js',
          content: 'console.log("Hello from file3.js!");'
        }
      ]
    };
  }

  $: folder = getFolder();
</script>

<style>
  .container {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
  }

  .files-container {
    grid-column: 1 / 2;
  }

  .download-container {
    grid-column: 2 / 3;
  }
</style>
