<template>
  <Accordion style="padding-top: 50px;">
    <AccordionItem title="Sync/create new folder">
      <p>
        --------------------------------------------------------------------------------------------------------<br><br>
        I recommend using Stoic wallet.<br><br>
        1/ Click [Create New] to select a local folder and wait a bit for it to load and verify the folder.<br><br>
        2/ Click the [Sync] button to synchronize the folder with on the server.<br><br>
        When folder synchronization is complete, you can click the [Download] button to save the file locally.<br><br>
        WARNING: If you are not logged in, when you create a folder, the folder will be publicly accessible.<br><br>
        --------------------------------------------------------------------------------------------------------<br><br>
      </p>
    </AccordionItem>
    <AccordionItem title="Sync/merge folder local to on-chain">
      <p>
        --------------------------------------------------------------------------------------------------------<br><br>
        1/ Once the login is complete, the folders you created/synced will be loaded on your home page.<br><br>
        2/ Select the folder and click [Sync] button, a dialog will open to select the local folder you want to merge and sync.<br><br>
        After selecting a folder to sync, the application will process uploading files in the selected folder locally to the server, and download files from the server to the local.<br><br>
        When folder synchronization is complete, you can click the [Download] button to store all the files locally.<br><br>
        --------------------------------------------------------------------------------------------------------<br><br>
      </p>
    </AccordionItem>
    <AccordionItem title="Delete folder">
      <p>
        --------------------------------------------------------------------------------------------------------<br><br>
        Click the delete button if you want to delete folders and files on the server.<br><br>
        --------------------------------------------------------------------------------------------------------<br><br>
      </p>
    </AccordionItem>
  </Accordion>
</template>

<script>
  import {  Accordion, 
            AccordionItem} from "carbon-components-svelte";

  
    // console.log(process.env.NODE_ENV);
</script>
