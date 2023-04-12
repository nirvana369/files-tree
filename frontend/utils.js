import md5 from 'md5';
  
  function mergeFile(fileA, fileB) {
      let ret = {
        fId : fileA.fId && fileA.fId.length > 0 ? fileA.fId : fileB.fId,
        fName : fileA.fName,
        fType : fileA.fType,
        fCanister : fileA.fCanister.length > 0 ? fileA.fCanister : fileB.fCanister,
        fHash : fileA.fHash.length > 0 ? fileA.fHash : fileB.fHash,
        fData : fileA.fData && fileA.fData.length > 0 ? fileA.fData : fileB.fData && fileB.fData.length > 0 ? fileB.fData : [],
        fState : fileA.fState.hasOwnProperty('ready') ? fileA.fState : fileB.fState,
        children : fileA.children.length > 0 ? fileA.children : fileB.children,
      }; 
      return ret;
  }

  function mergeFolder(folderA, folderB) {
    let ret = {
      fId : folderA.fId.length > 0 ? folderA.fId : folderB.fId,
      fName : folderA.fName,
      fType : {directory : null},
      fCanister : folderA.fCanister.length > 0 ? folderA.fCanister : folderB.fCanister,
      fHash : folderA.fHash.length > 0 ? folderA.fHash : folderB.fHash,
      fData : folderA.fData,
      fState : folderA.fState,
      children : folderA.children.length > 0 ? folderA.children : folderB.children,
    }; 
    return ret;
}

  function mergeFileTree(leafA, leafB) {
      let ret = mergeFolder(leafA, leafB); // or leafB
      let children = [];
      let markB = {};
      for(const i of leafA.children[0]) {
        let isSame = false;
          for(const j of leafB.children[0]) {
              if (markB[j.fName] != true && i.fName === j.fName) {
                if (getIsFolder(i.fType) && getIsFolder(j.fType)) {
                    isSame = true;
                    markB[j.fName] = true;
                    let c = mergeFileTree(i, j);
                    children.push(c);
                } else if (!getIsFolder(i.fType) && !getIsFolder(j.fType)) {
                    isSame = true;
                    markB[j.fName] = true;
                    children.push(mergeFile(i, j));
                }
              }
          }
          if (isSame == false) {
            children.push(i);
          }
      }
      for(const j of leafB.children[0]) {
          if (markB[j.fName] != true) {
            children.push(j);
          }
      }
      ret.children = [children];
      return ret;
  }

  function getFileTreeData(fileTree) {
    let fileArray = recursiveCollectFileData(fileTree);
    let ret = {};
    for (const f of fileArray) {
        ret[f.fHash[0]] = f;
    }
    return ret;
  }

  function recursiveCollectFileData(fileTree) {
      if (getIsFolder(fileTree.fType)) {
          let ret = []; 
          for (const child of fileTree.children[0]) {
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
            fId : [],
            fName : dirHandle.name,
            fType : {directory : null},
            fCanister : [],
            fHash : [],
            fData : [],
            fState : {empty : null},
            children : [[]]
          }; 
      while (entry.value) {
        let obj = entry.value[1];
        if (obj.kind == "directory") {
          let sub = await traverseDirectory(obj, callback);
          ret.children[0].push(sub);
        } else if (obj.kind == "file") {
          const fileHandle = await obj.getFile();
          const file = await fileHandle.arrayBuffer();
          // callback(obj.name, file);
          var ia = new Uint8Array(file);  // ArrayBuffer -> Uint8Array
          var nat8Arr = Array.from(ia)    // Uint8Array -> [Nat8]
          let hash = md5(nat8Arr);
          // console.log(new Uint8Array(nat8Arr[0]).buffer);  // convert [Nat8] -> to file
          let f = {
            fId : [],
            fName : obj.name,
            fType : {file : null},
            fCanister : [],
            fHash : [hash],
            fData : [nat8Arr],
            fState : {empty : null},
            children : [[]]
          };
          ret.children[0].push(f);
        }
        
        entry = await entries.next();
      }
      return ret;
    }
    
  function isHashEqual(hashA, hashB) {
    if (hashA.length > 0 && hashA.length == hashB.length) {
       if (hashA[0] === hashB[0]) {
          return true;
       }
    }
    return false;
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
  
export {  getIsFolder, 
          traverseDirectory, 
          mergeFileTree,
          getFileTreeData,
          mergeUInt8Arrays
        };