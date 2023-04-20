<template>
  <Accordion style="padding-top: 50px;">
    {#if promiseInfo != null}
      {#if type == 1}
        <AccordionItem title="Server Infomation">
            {#await promiseInfo then list}
                <DataTable
                headers={[
                  { key: "id", value: "Principal" },
                  { key: "cycle", value: "Cycle available" },
                ]}
                rows={list}
              />
            {/await}
        </AccordionItem>
      {:else}
        <AccordionItem title="Storage Infomation">
            {#await promiseInfo then list}
            <DataTable
              headers={[
                { key: "id", value: "Principal" },
                { key: "mem", value: "Memory available" },
              ]}
              rows={list}
            />
            {/await}
        </AccordionItem>
      {/if}
    {/if}
  </Accordion>
  {#if promise != null}
        {#await promise then list}
      <DataTable
          headers={[
            { key: "name", value: "Actor/action" },
            { key: "count", value: "Number call" },
            { key: "avgProcTime", value: "Average process time" },
            { key: "totalProcTime", value: "Total process time" },
          ]}
          rows={list}
          style="padding-top: 50px;"/>
    {/await}
  {/if}
</template>

<script>
  import { DataTable,
            Accordion, 
            AccordionItem, } from "carbon-components-svelte";
  import { useCanister } from "@connect2ic/svelte";
  
  export let type;

  const [fileTreeRegistry] = useCanister("registry")
  const [fileStorage] = useCanister("storage")


  let promise = getProfile();   
  
  let promiseInfo = type == 1 ? $fileTreeRegistry.getServerInfo() : $fileTreeRegistry.getStorageInfo();
  
  async function getProfile() {
    let x = type == 1 ? await $fileTreeRegistry.getProfiler() : await $fileStorage.getProfiler();
    let c = 0;
    let arr = [];
    for (const i of x) {
          i.name = i.id;
          i.id = c++;
          arr.push(i);
    }
    return arr;
  }
  

</script>

<style>

</style>
