<template>
  <Column sm={1} md={4} lg={9}><FileTree bind:file={fileTree} rootId={fileTree.id}/></Column>
  {#if inAction}
    <Column sm={1} md={2} lg={6}><InlineLoading /></Column>
  {:else}
    <Column sm={1} md={2} lg={2} style="padding-top:33px;"><DeleteButton folder={fileTree} 
                                                                          toogleInAction={toogleInAction} 
                                                                          reload={reloadAction}/></Column>
    <Column sm={1} md={2} lg={2}><SyncButton bind:folder={fileTree} 
                                              directoryHandle={directoryHandle} 
                                              toogleModal={toogleModal} 
                                              toogleInAction={toogleInAction} 
                                              toogleEnableDownload={toogleEnableDownload}
                                              reload={reload}/></Column>
    {#if enableDownload}
      <Column sm={1} md={2} lg={2} style="padding-top:33px;"><DownloadButton  folder={fileTree} 
                                                                              toogleInAction={toogleInAction}/></Column>
      {/if}
  {/if}
</template>

<script>
  import FileTree from './FileTree.svelte';
  import SyncButton from './SyncButton.svelte';
  import DeleteButton from './DeleteButton.svelte';
  import DownloadButton from "./DownloadButton.svelte";
  import { Column, InlineLoading } from "carbon-components-svelte";
  import { walk, logging } from "../../utils";

  export let fileTree;
  export let directoryHandle;
  export let toogleModal;
  export let reloadAction;

  let inAction = false;
  let enableDownload = false;
  

  function reload(f) {
    walk(fileTree, function syncCallback(file) {
        if (f.id == file.id && f.name == file.name && f.hash == file.hash) {
            file.state = f.state;
        } 
    });
  };

  function toogleEnableDownload(mode, f) {
      fileTree = f;
      enableDownload = mode;
  }

  function toogleInAction(mode) {
    inAction = mode;
  };

  function getFolder() {
    logging("SHOW FOLDER");
    logging(fileTree);
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
