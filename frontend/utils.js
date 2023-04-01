
function convert2CandidFileTree(fileTree) {
    if (fileTree.kind == "directory") {
      let dir = {
            fId : fileTree.fId,
            fName : fileTree.fName,
            fType : {directory : null},
            fCanister : fileTree.fCanister,
            fHash : fileTree.fHash,
            fData : fileTree.fData,
            children : fileTree.children.length > 0 ? [fileTree.children] : []
          }; 
          dir.children = [fileTree.children.map(d => convert2CandidFileTree(d))];
          
          return dir;
    } 
    let file = {
          fId : fileTree.fId,
          fName : fileTree.fName,
          fType : {file : null},
          fCanister : fileTree.fCanister,
          fHash : fileTree.fHash,
          fData : fileTree.fData,
          children : []
        };
    return file;
  }

export { convert2CandidFileTree };