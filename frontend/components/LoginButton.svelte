<template>
  <div class="auth-section">
    <ConnectButton />
  </div>
  <ConnectDialog />
</template>

<script>
  import { ConnectButton, ConnectDialog, useConnect } from "@connect2ic/svelte"

  const { isConnected, principal, activeProvider } = useConnect({
    onConnect: () => {
        console.log("sign in");
      // Signed in
        // test();
    },
    onDisconnect: () => {
      // Signed out
      console.log("sign out");
    }
  })
    
</script>
