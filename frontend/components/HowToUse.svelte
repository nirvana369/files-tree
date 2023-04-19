<template>
  <Accordion style="padding-top: 50px;">
    <AccordionItem title="Sync/create new folder">
      <p>
        1/ Click [Create new] to pick local folder and wait a little to load and verify folder.<br><br>
        2/ Click [Sync] button to sync folder to on-chain.<br><br>
        When folder sync complete, you can click [Download] button to store files to local.<br><br>
        WARN : If you not login, when you created folder, it will be public access.
      </p>
    </AccordionItem>
    <AccordionItem title="Sync/merge folder local to on-chain">
      <p>
        1/ After login completed, folders you created/synced will loaded on your screen.<br><br>
        2/ Choose folder and click [Sync] button, dialog will open to choose local folder you want to merge and sync.<br><br>
        When folder sync complete, you can click [Download] button to sync all files to local.
      </p>
    </AccordionItem>
    <AccordionItem title="Delete folder">
      <p>
        Click delete button if you want to delete folder & files on-chain.
      </p>
    </AccordionItem>
    <AccordionItem title="Server Infomation">
      {#if promiseRegistry != null}
        {#await promiseRegistry then list}
            <DataTable
            headers={[
              { key: "id", value: "Principal" },
              { key: "cycle", value: "Cycle available" },
            ]}
            rows={list}
          />
        {/await}
      {/if}
      
    </AccordionItem>
    <AccordionItem title="Storage Infomation">
      {#if promiseStorage != null}
        {#await promiseStorage then list}
        <DataTable
          headers={[
            { key: "id", value: "Principal" },
            { key: "mem", value: "Memory available" },
          ]}
          rows={list}
        />
        {/await}
      {/if}
    </AccordionItem>
  </Accordion>
</template>

<script>
  import {  Accordion, 
            AccordionItem,
            DataTable} from "carbon-components-svelte";
  import { useCanister } from "@connect2ic/svelte";
    const [fileTreeRegistry] = useCanister("registry")

    let promiseRegistry = $fileTreeRegistry.getServerInfo();
    let promiseStorage = $fileTreeRegistry.getStorageInfo();
</script>
