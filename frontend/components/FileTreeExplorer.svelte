<script>
  import logo from "../assets/dfinity.svg"
  import FileTreeItem from "./filetree/FileTreeItem.svelte";
  import { onMount } from 'svelte';
  import { useCanister } from "@connect2ic/svelte";
  import { localFileTrees, serverFileTrees, syncFiles } from "../stores.js"
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
            Button } from "carbon-components-svelte";
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
  let directoryHandle;
  let directoryHandlePointer = {};
  let auth = false;
  let open = false;

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
    let fileTree = await traverseDirectory(directoryHandle, function(name, content) {
        const file = { name: name, content: content };
        console.log("your file is : " + name);
        console.log(file);
        // save file to localDB ?
      });
    // let r = await objectStore.add(fileTree);
    let tmp = await $fileTreeRegistry.verifyFileTree(fileTree);
    directoryHandlePointer[fileTree.fName] = directoryHandle;
    // after verify if data changing -> update fileTree
    $localFileTrees = [...$localFileTrees, fileTree];
    console.log("verify done");
    console.log(tmp);
    toogleSyncModal(false);
  }

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
          let ret = await $fileTreeRegistry.getListFileTree();
          if (ret.ok) {
              $serverFileTrees = ret.ok;
              $localFileTrees = [...$localFileTrees, ...$serverFileTrees];
          } else {
            console.log("getListFileTree #ERR:");
            console.log(ret);
          }
          let whoami = await $fileTreeRegistry.whoami();
          console.log("WHO ARE YOU 2");
          console.log(whoami);
          
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
        {#each $localFileTrees as f}
        <Row padding style="border: 1px solid white;border-radius: 10px;padding;margin-top: 5px;">
          <FileTreeItem fileTree={f} directoryHandle={directoryHandlePointer[f.fName]} toogleModal={toogleSyncModal}/>
        </Row>
        {/each}
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
      {#each $syncFiles as fname}
        <ListItem>{fname}</ListItem>
      {/each}
    </OrderedList>
    </Modal>
  </div>
</template>

<style>
</style>