<template>
  <Column sm={1} md={4} lg={9}><FileTree file={fileTree} /></Column>
  <Column sm={1} md={2} lg={1} style="padding-top:33px;"><DeleteButton folder={fileTree} /></Column>
  <Column sm={1} md={2} lg={6}><SyncButton folder={fileTree} directoryHandle={directoryHandle} toogleModal={toogleModal} /></Column>
</template>

<script>
  import FileTree from './FileTree.svelte';
  import SyncButton from './SyncButton.svelte';
  import DeleteButton from './DeleteButton.svelte';

  import { Column } from "carbon-components-svelte";

  export let fileTree;
  export let directoryHandle;
  export let toogleModal;

  function getFolder() {
    console.log("SHOW FOLDER");
    console.log(fileTree);
    return fileTree || getDefaultFolder();
  }

  function getDefaultFolder() {
    return {
      fName: 'root',
      children: [[
        {
          fName: 'folder1',
          children: [[
            {
              fName: 'file1-1.js',
              content: 'console.log("Hello from file1-1.js!");'
            },
            {
              fName: 'file1-2.js',
              content: 'console.log("Hello from file1-2.js!");'
            }
          ]]
        },
        {
          fName: 'folder2',
          children: [[
            {
              fName: 'file2-1.js',
              content: 'console.log("Hello from file2-1.js!");'
            },
            {
              fName: 'file2-2.js',
              content: 'console.log("Hello from file2-2.js!");'
            }
          ]]
        },
        {
          fName: 'file3.js',
          content: 'console.log("Hello from file3.js!");'
        }
      ]]
    };
  }

  $: fileTree = getFolder();
</script>

<style>

</style>
