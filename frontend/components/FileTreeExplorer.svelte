<script>
  import logo from "../assets/dfinity.svg"
  import FileTreeItem from "./filetree/FileTreeItem.svelte";
  import { onMount } from 'svelte';
  import { useCanister } from "@connect2ic/svelte";
  import { localFileTrees, serverFileTrees, syncFiles, user } from "../stores.js"
  import { traverseDirectory} from "../utils";
  import { useConnect } from "@connect2ic/svelte"
  import LoginButton from "./LoginButton.svelte"
  import HowToUse from "./HowToUse.svelte";
  import {  ProgressBar,
            Modal, 
            Grid, 
            Row,
            OrderedList, 
            ListItem, 
            Button,
            Loading,
            FileUploader } from "carbon-components-svelte";
  import {
    Header,
    HeaderNav,
    HeaderUtilities,
  } from "carbon-components-svelte";

  const { principal } = useConnect({
    onConnect: () => {
      auth = true;
      // Signed in
    },
    onDisconnect: () => {
      // Signed out
    }
  })
  const [fileTreeRegistry] = useCanister("registry")
  const [fileTest] = useCanister("test")

  let directoryHandle;
  let directoryHandlePointer = {};
  let auth = false;
  let open = false;
  let fileMapPointer = {};

  async function selectFolder() {
    try {
        directoryHandle = await window.showDirectoryPicker();
        await checkFileTree();
        // document.getElementById("store-button").disabled = false;
      } catch (error) {
        console.error("Failed to select folder:", error);
      }
  }

  async function checkFileTree() {
    if (!directoryHandle) {
      alert("Please select a folder.");
      return;
    }
    toogleSyncModal(true);
    let fileMap = {};
    let fileTree = await traverseDirectory(directoryHandle, function(name, hash, content) {
        const file = { name: name, content: content };
        console.log("your file is : " + name);
        console.log(file);
        fileMap[hash] = content;
        // save file to localDB ?
      });
    fileMapPointer[fileTree.name] = fileMap;
    
    console.log(fileTree);
    // let r = await objectStore.add(fileTree);
    let tmp = await $fileTreeRegistry.verifyFileTree(fileTree);

    
    directoryHandlePointer[fileTree.name] = directoryHandle;
    // after verify if data changing -> update fileTree
    $localFileTrees = [fileTree];
    reload();

    console.log("verify done");
    console.log(tmp);
    toogleSyncModal(false);
  }

  function reload() {
    promise = reloadFileTrees();
  }

  async function reloadFileTrees() {
    let list = [...$localFileTrees];
    let ret = await $fileTreeRegistry.getListFileTree();
    if (ret.ok) {
        $serverFileTrees = ret.ok;
        list = [...list, ...$serverFileTrees];
        console.log("LIST TREE");
        console.log(list);
        return list;
    } else {
      console.log("getListFileTree #ERR:");
      console.log(ret);
    }
    return list;
  }

  let promise = null;

  onMount(async () => {
    var startTime = new Date().getTime();
    var interval = setInterval(async function(){
        if(new Date().getTime() - startTime > 60000){
            clearInterval(interval);
            return;
        }
        //do whatever here..
        if (auth) {
          clearInterval(interval);
          // let ret = await $fileTreeRegistry.getListFileTree();
          // if (ret.ok) {
          //     $serverFileTrees = ret.ok;
          //     $localFileTrees = [...$localFileTrees, ...$serverFileTrees];
          // } else {
          //   console.log("getListFileTree #ERR:");
          //   console.log(ret);
          // }
          reload();

          let whoami = await $fileTreeRegistry.whoami();
          console.log("WHO ARE YOU 2");
          console.log(whoami);
          $user = $principal;
          // code to fetch tree data from server
        }
    }, 2000);  

    let whoami = await $fileTreeRegistry.whoami();
    console.log("WHO ARE YOU 1");
    console.log(whoami);
    // code to fetch tree data from server
  });

  function toogleSyncModal(state) {
    console.log("toogle modal");
    open = state;
  }

</script>
<template>
  <div class="container">
    <Header company="Decentralize" platformName="FileTrees">
      <svelte:fragment slot="skip-to-content">
        <img src={logo} alt="DFiles logo" style="height: 50%;">
      </svelte:fragment>
      <HeaderNav>

        <Button on:click={() => selectFolder()} size="small" kind="ghost">Create new</Button>
      </HeaderNav>

      <HeaderUtilities>
        <LoginButton />
      </HeaderUtilities>
    </Header>
    
    <HowToUse/>

    <Grid fullWidth style="padding-top: 50px;">
      {#if promise != null}
        {#await promise then list}
          {#each list as f}
          <Row padding style="border: 1px solid white;border-radius: 10px;padding;margin-top: 5px;">
            <FileTreeItem fileTree={f} 
                          directoryHandle={directoryHandlePointer[f.name]} 
                          toogleModal={toogleSyncModal} 
                          reloadAction={reload}
                          fileMap={fileMapPointer[f.name] ? fileMapPointer[f.name] : {}}/>
          </Row>
          {/each}
        {/await}
      {:else}
          <Loading/>
      {/if}
        
    </Grid>
    
  
    <Modal 
      preventCloseOnClickOutside 
      size="lg" bind:open
      modalHeading="Sync File Tree"
      passiveModal
      hasScrollingContent
    >
    <ProgressBar
      labelText="sync..."
    />
    <OrderedList>
      {#each $syncFiles as name}
        <ListItem>{name}</ListItem>
      {/each}
    </OrderedList>
    </Modal>
  </div>
</template>

<style>
</style>