import md5 from 'md5';
  
  function mergeFile(fileA, fileB) {
      let ret = {
        id : fileA.id > 0 ? fileA.id : fileB.id,
        name : fileA.name,
        fType : fileA.fType,
        canisterId : fileA.canisterId != "" ? fileA.canisterId : fileB.canisterId,
        hash : fileA.hash != "" ? fileA.hash : fileB.hash,
        data : fileA.data && fileA.data.length > 0 ? fileA.data : (fileB.data && fileB.data.length > 0 ? fileB.data : []),
        state : fileA.state.hasOwnProperty('ready') ? fileA.state : fileB.state,
        size : fileA.size > 0 ? fileA.size : fileB.size,
        totalChunk : fileA.totalChunk > 0 ? fileA.totalChunk : fileB.totalChunk,
        children : [],
      }; 
      return ret;
  }

  function mergeFolder(folderA, folderB) {
    let ret = {
      id : folderA.id > 0 ? folderA.id : folderB.id,
      name : folderA.name,
      fType : {directory : null},
      canisterId : folderA.canisterId != "" ? folderA.canisterId : folderB.canisterId,
      hash : folderA.hash != "" ? folderA.hash : folderB.hash,
      data : folderA.data,
      state : folderA.state,
      size : folderA.size > 0 ? folderA.size : folderB.size,
      totalChunk : folderA.totalChunk > 0 ? folderA.totalChunk : folderB.totalChunk,
      children : [] // combine logic at mergeFileTree(a, b)
    }; 
    return ret;
}

  function mergeFileTree(leafA, leafB) {
      let ret = mergeFolder(leafA, leafB); // or leafB
      let children = [];
      let markB = {};
      for(const i of leafA.children) {
          let isSame = false;
          for(const j of leafB.children) {
              if (markB[j.name] != true && i.name === j.name) {
                if (getIsFolder(i.fType) && getIsFolder(j.fType)) {
                    isSame = true;
                    markB[j.name] = true;
                    let c = mergeFileTree(i, j);
                    children.push(c);
                } else if (!getIsFolder(i.fType) && !getIsFolder(j.fType)) {
                    isSame = true;
                    markB[j.name] = true;
                    children.push(mergeFile(i, j));
                }
              }
          }
          if (isSame == false) {
            children.push(i);
          }
      }
      for(const j of leafB.children) {
          if (markB[j.name] != true) {
            children.push(j);
          }
      }
      ret.children = children;
      return ret;
  }

  function getFileTreeData(fileTree) {
    let fileArray = recursiveCollectFileData(fileTree);
    return fileArray;
  }

  function recursiveCollectFileData(fileTree) {
      if (getIsFolder(fileTree.fType)) {
          let ret = []; 
          for (const child of fileTree.children) {
              let f = recursiveCollectFileData(child);
              ret = [...ret,...f];
          }
          return ret;
      } else {
          return [fileTree];
      }
  }

  async function traverseDirectory(dirHandle, callback) {
      let entries = await dirHandle.entries();
      let entry = await entries.next();
      let ret = {
            id : 0,
            name : dirHandle.name,
            fType : {directory : null},
            canisterId : "",
            hash : "",
            data : [],
            state : {empty : null},
            size : 0,
            totalChunk : 0,
            children : []
          }; 
      while (entry.value) {
        let obj = entry.value[1];
        if (obj.kind == "directory") {
          let sub = await traverseDirectory(obj, callback);
          ret.children.push(sub);
        } else if (obj.kind == "file") {
          const fileHandle = await obj.getFile();
          const file = await fileHandle.arrayBuffer();
          
          var ia = new Uint8Array(file);  // ArrayBuffer -> Uint8Array
          var nat8Arr = Array.from(ia)    // Uint8Array -> [Nat8]
          let hash = md5(nat8Arr);
          // console.log(new Uint8Array(nat8Arr[0]).buffer);  // convert [Nat8] -> to file
          const chunkLength = 1000000;
          callback(obj.name, hash, nat8Arr);
          let f = {
            id : 0,
            name : obj.name,
            fType : {file : null},
            canisterId : "",
            hash : hash,
            data : nat8Arr,
            size : nat8Arr.length,
            totalChunk : Math.ceil(nat8Arr.length / chunkLength),
            state : {empty : null},
            children : []
          };
          ret.children.push(f);
        }
        
        entry = await entries.next();
      }
      return ret;
    }

  function getIsFolder(fileType) {
    if (fileType && fileType.hasOwnProperty('directory')) {
      return true;
    }
    return false;
    // return file.children && file.children.length > 0;
  }
  
  function mergeUInt8Arrays(a1, a2) {
    // sum of individual array lengths
    var mergedArray = new Uint8Array(a1.length + a2.length);
    mergedArray.set(a1);
    mergedArray.set(a2, a1.length);
    return mergedArray;
  }
  
  async function downloadFile(dirHandle, folder, fileMap) {
    console.log("UTILS DOWNLOAD file");
    console.log(fileMap);
    console.log(folder);
    await createDirectory(dirHandle, folder, fileMap);
  }

  async function createFile(fileHandle, content) {
    // convert [uint8] -> ArrayBuffer -> Blob
    let blob = new Blob([new Uint8Array(content).buffer]);
    /**
     * Secure context : fileHandle.createWritable()
     * This feature is available only in secure contexts (HTTPS), in some or all supporting browsers.
     */
    const writable = await fileHandle.createWritable();
    // Write the contents of the file to the stream.
    await writable.write(blob);
    // Close the file and write the contents to disk.
    await writable.close();
  }

  async function createDirectory(dirEntry, fileTree, fileMap) {
    const curDir = await dirEntry.getDirectoryHandle(fileTree.name, { create: true });
    for (const child of fileTree.children) {
        if (getIsFolder(child.fType)) {
           createDirectory(curDir, child);
        } else {
          const data = fileMap[child.hash];
          if (data && data.length > 0) {
            let curFile = await curDir.getFileHandle(child.name, { create: true });
            createFile(curFile, data);
          } else {
            alert("File: " + child.name + " | hash: " + child.hash + " data is empty");
          }
        }
      }
  }

export {  getIsFolder, 
          traverseDirectory, 
          mergeFileTree,
          getFileTreeData,
          mergeUInt8Arrays,
          downloadFile
        };