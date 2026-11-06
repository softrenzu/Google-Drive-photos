(() => {
  "use strict";
  const $ = id => document.getElementById(id);
  const ui = {
    client:$("client-id"), connect:$("connect"), disconnect:$("disconnect"), connection:$("connection-status"),
    files:$("photo-input"), analyze:$("analyze"), results:$("results"), summary:$("summary"),
    upload:$("upload"), uploadStatus:$("upload-status"), driveLink:$("drive-link"),
    panel:$("progress-panel"), progress:$("progress"), label:$("progress-label"), count:$("progress-count")
  };
  const clientStorage="rooomtech-webdocs-oauth-client";
  const scope="https://www.googleapis.com/auth/drive.file";
  const folderName="iPhone_Business_Documents";
  const docWords=["請求書","領収書","見積書","契約書","納品書","発注書","請求明細","支払明細","経費精算","invoice","receipt","quotation","purchaseorder"];
  const contextWords=["合計","金額","税抜","税込","支払","振込","発行","円","御中","住所","明細","数量","単価","消費税","total","amount","date","tax"];
  const excluded=["マイナンバー","個人番号","運転免許証","パスポート","passport","在留カード","健康保険証","身分証明書","学生証","免許証"];
  let oauth,token=null,expires=0,detector=null,faceDetector=null,ocr=null,entries=[],busy=false;
  ui.client.value=localStorage.getItem(clientStorage)||"";
  const say=message=>{ui.uploadStatus.textContent=message;};
  const progress=(msg,n,total)=>{
    ui.panel.hidden=false;ui.label.textContent=msg;ui.count.textContent=n+" / "+total;
    ui.progress.value=total?Math.round(n*100/total):0;
  };
  const validClient=s=>/^[0-9]+-[a-zA-Z0-9_-]+\.apps\.googleusercontent\.com$/.test(s);
  const clear=()=>{
    entries.forEach(x=>{if(x.url)URL.revokeObjectURL(x.url);});
    entries=[];ui.results.replaceChildren();
    const p=document.createElement("p");p.className="empty";
    p.textContent="写真を選んで「判定」を押すと、ここに結果が表示されます。";
    ui.results.append(p);ui.upload.disabled=true;ui.summary.hidden=true;ui.driveLink.hidden=true;say("");
  };
  ui.client.addEventListener("change",()=>{
    const s=ui.client.value.trim();if(validClient(s))localStorage.setItem(clientStorage,s);
  });
  ui.files.addEventListener("change",()=>{
    clear();
    const n=ui.files.files?.length||0;ui.analyze.disabled=!n;
    if(n)ui.results.querySelector(".empty").textContent=n+"枚を選びました。「選んだ写真を判定」を押してください。";
  });

  ui.connect.addEventListener("click",()=>{
    const client=ui.client.value.trim();
    if(!validClient(client)){ui.connection.textContent="ウェブアプリ用のOAuthクライアントIDを入力してください。";return;}
    if(!window.google?.accounts?.oauth2){ui.connection.textContent="Googleの認証機能を読み込めませんでした。";return;}
    localStorage.setItem(clientStorage,client);
    oauth=google.accounts.oauth2.initTokenClient({
      client_id:client,scope,
      callback:r=>{
        if(r.error||!r.access_token){ui.connection.textContent="Google認証エラー："+(r.error||"キャンセルされました");return;}
        token=r.access_token;expires=Date.now()+(Number(r.expires_in||3600)-60)*1000;
        ui.connection.textContent="Google Driveに接続しました。";
        ui.connect.textContent="再認証";ui.disconnect.hidden=false;
      },
      error_callback:e=>{ui.connection.textContent="Google認証エラー："+(e?.type||"ログイン画面を開けません");}
    });
    oauth.requestAccessToken({prompt:"consent"});
  });
  ui.disconnect.addEventListener("click",()=>{
    const old=token;token=null;expires=0;
    if(old&&window.google?.accounts?.oauth2)google.accounts.oauth2.revoke(old,()=>{});
    ui.connection.textContent="接続を解除しました。";ui.connect.textContent="Googleアカウントで連携する";
    ui.disconnect.hidden=true;
  });

  async function convert(file){
    const url=URL.createObjectURL(file),img=new Image();
    try{
      const ready=new Promise((ok,fail)=>{img.onload=ok;img.onerror=()=>fail(new Error("画像を読み込めません（HEICはJPEGに変換してください）"));});
      img.src=url;await ready;
      const width=img.naturalWidth,height=img.naturalHeight;
      if(!width||!height)throw new Error("画像サイズが不明です");
      const scale=Math.min(1,2200/Math.max(width,height));
      const canvas=document.createElement("canvas");
      canvas.width=Math.max(1,Math.round(width*scale));
      canvas.height=Math.max(1,Math.round(height*scale));
      const ctx=canvas.getContext("2d",{willReadFrequently:true});
      if(!ctx)throw new Error("画像変換ができません");
      ctx.fillStyle="#fff";ctx.fillRect(0,0,canvas.width,canvas.height);
      ctx.drawImage(img,0,0,canvas.width,canvas.height);
      const blob=await new Promise((ok,fail)=>canvas.toBlob(b=>b?ok(b):fail(new Error("JPEG変換に失敗")),"image/jpeg",.86));
      return {canvas,blob};
    }finally{URL.revokeObjectURL(url);}
  }

  async function models(){
    if(!window.Tesseract?.createWorker||!window.cocoSsd?.load||!window.blazeface?.load||!window.tf)
      throw new Error("写真の安全判定ライブラリが読み込めません。通信を確認してください");
    if(!detector){progress("人物検出AIを読み込み中",0,1);detector=await cocoSsd.load({base:"lite_mobilenet_v2"});}
    if(!faceDetector){progress("顔検出AIを読み込み中",0,1);faceDetector=await blazeface.load();}
    if(!ocr){progress("日本語の文字認識を読み込み中",0,1);ocr=await Tesseract.createWorker(["jpn","eng"],1);}
  }

  async function inspect(canvas){
    // Detector errors fail closed. A browser model cannot guarantee that all people are found.
    const predictions=await detector.detect(canvas,20,.15);
    if(predictions.some(x=>x.class==="person"&&x.score>=.15))
      return {ok:false,reason:"人物を検出したため除外"};
    const faces=await faceDetector.estimateFaces(canvas,false);
    if(faces.length)return {ok:false,reason:"顔写真を検出したため除外"};
    const result=await ocr.recognize(canvas);
    const data=result?.data||{},text=String(data.text||"").replace(/\s+/g,"").toLowerCase();
    const lines=(data.lines||[]).filter(x=>x.text?.trim()).length;
    if(excluded.some(word=>text.includes(word.toLowerCase())))
      return {ok:false,reason:"身分証・個人情報を含むため除外"};
    if(text.length<30||(lines&&lines<3)||Number(data.confidence||0)<40)
      return {ok:false,reason:"書類か判断できず除外"};
    if(!docWords.some(word=>text.includes(word.toLowerCase())))
      return {ok:false,reason:"業務書類と判定できず除外"};
    if(!contextWords.some(word=>text.includes(word.toLowerCase())))
      return {ok:false,reason:"書類の裏付けが不足したため除外"};
    return {ok:true,reason:"業務書類の候補（人物検出の見逃しに注意）"};
  }

  const updateButtons=()=>{
    const n=entries.filter(x=>x.ok&&x.selected).length;
    ui.upload.disabled=busy||!n;
    ui.upload.textContent=n?"選んだ"+n+"件をGoogle Driveへ保存":"送信する書類がありません";
  };
  const render=()=>{
    ui.results.replaceChildren();
    if(!entries.length){
      const p=document.createElement("p");p.className="empty";p.textContent="判定結果がありません。";ui.results.append(p);
    }
    entries.forEach(item=>{
      const card=document.createElement("article");card.className="result "+(item.ok?"eligible":"blocked");
      if(item.url){
        const img=document.createElement("img");img.src=item.url;img.alt=item.file.name+"の確認画像";img.loading="lazy";card.append(img);
      }
      const body=document.createElement("div");body.className="result-body";
      const name=document.createElement("div");name.className="result-name";name.textContent=item.file.name;
      const info=document.createElement("div");info.className="result-status";info.textContent=item.reason;
      body.append(name,info);
      if(item.ok){
        const label=document.createElement("label"),input=document.createElement("input");
        input.type="checkbox";input.checked=item.selected;
        input.setAttribute("aria-label",item.file.name+"を送信する");
        input.addEventListener("change",()=>{item.selected=input.checked;updateButtons();});
        label.append(input,document.createTextNode("確認して送信する"));body.append(label);
      }
      card.append(body);ui.results.append(card);
    });
    const eligible=entries.filter(x=>x.ok).length;
    ui.summary.hidden=false;
    ui.summary.textContent="書類候補 "+eligible+"件 / 除外 "+(entries.length-eligible)+"件。プレビューを確認してください。";
    updateButtons();
  };
  ui.analyze.addEventListener("click",async()=>{
    if(busy)return;
    const files=Array.from(ui.files.files||[]).slice(0,25);
    if(!files.length)return;
    clear();busy=true;ui.analyze.disabled=true;
    try{
      await models();
      for(let i=0;i<files.length;i++){
        const file=files[i];progress("端末内で判定："+file.name,i,files.length);
        try{
          if(file.size>40*1024*1024)throw new Error("40MB超の画像は判定しません");
          const image=await convert(file);
          const decision=await inspect(image.canvas);
          entries.push({file,blob:decision.ok?image.blob:null,url:URL.createObjectURL(image.blob),
            ok:decision.ok,selected:decision.ok,reason:decision.reason});
        }catch(error){
          entries.push({file,ok:false,selected:false,reason:"判定失敗・送信しません："+error.message});
        }
        await new Promise(ok=>setTimeout(ok,0));
      }
      progress("判定完了",files.length,files.length);render();
      if((ui.files.files?.length||0)>25)say("一度に判定するのは25枚までです。残りは改めて選択してください。");
    }catch(error){say("安全のため送信を中止しました："+error.message);}
    finally{busy=false;ui.analyze.disabled=false;updateButtons();}
  });

  async function googleJSON(url,opts={}){
    if(!token||Date.now()>expires)throw new Error("Google認証が切れました。「Googleアカウントで連携する」を押してください");
    const res=await fetch(url,{...opts,headers:{...opts.headers,Authorization:"Bearer "+token}});
    if(!res.ok)throw new Error("Google Drive "+res.status+"："+(await res.text()).slice(0,170));
    return res.json();
  }
  async function folder(){
    const key="rooomtech-webdocs-folder:"+ui.client.value.trim();
    const saved=localStorage.getItem(key);
    if(saved){
      try{await googleJSON("https://www.googleapis.com/drive/v3/files/"+encodeURIComponent(saved)+"?fields=id,name");return saved;}
      catch(_){localStorage.removeItem(key);}
    }
    const created=await googleJSON("https://www.googleapis.com/drive/v3/files?fields=id,name",{
      method:"POST",headers:{"Content-Type":"application/json"},
      body:JSON.stringify({name:folderName,mimeType:"application/vnd.google-apps.folder"})
    });
    if(!created.id)throw new Error("保存先の作成に失敗");
    localStorage.setItem(key,created.id);return created.id;
  }
  async function hashImage(blob){
    const data=await crypto.subtle.digest("SHA-256",await blob.arrayBuffer());
    return Array.from(new Uint8Array(data),x=>x.toString(16).padStart(2,"0")).join("");
  }
  async function save(item,folderID){
    const hash=await hashImage(item.blob);
    const query="appProperties has { key='documentHash' and value='"+hash+"' } and trashed=false";
    const check=await googleJSON("https://www.googleapis.com/drive/v3/files?fields=files(id)&pageSize=1&q="+encodeURIComponent(query));
    if(check.files?.length)return "同じ書類が保存済みのため送信を省略";
    const time=new Date().toISOString().replace(/[^0-9]/g,"").slice(0,14);
    const meta={name:"BusinessDocument_"+time+"_"+hash.slice(0,12)+".jpg",
      mimeType:"image/jpeg",parents:[folderID],appProperties:{documentHash:hash}};
    const boundary="rooomtech"+crypto.randomUUID().replaceAll("-","");
    const multipart=new Blob([
      "--"+boundary+"\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n",
      JSON.stringify(meta)+"\r\n",
      "--"+boundary+"\r\nContent-Type: image/jpeg\r\n\r\n",
      item.blob,"\r\n--"+boundary+"--"
    ],{type:"multipart/related; boundary="+boundary});
    const result=await googleJSON("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name",{
      method:"POST",headers:{"Content-Type":multipart.type},body:multipart
    });
    if(!result.id)throw new Error("送信結果が確認できません");
    return "Google Driveへ送信済み";
  }
  ui.upload.addEventListener("click",async()=>{
    if(busy)return;
    const items=entries.filter(x=>x.ok&&x.selected);
    if(!items.length)return;
    if(!token||Date.now()>expires){say("Googleアカウントとの連携が必要です。");return;}
    if(!confirm("プレビューを確認した"+items.length+"件をGoogle Driveへ保存します。人物や個人情報を含んでいないか確認しましたか？"))return;
    busy=true;ui.upload.disabled=true;
    try{
      const folderID=await folder();let done=0;
      for(const item of items){
        progress("Google Driveへ送信中",done,items.length);
        try{item.reason=await save(item,folderID);item.ok=false;item.selected=false;done++;}
        catch(error){item.reason="送信に失敗："+error.message;break;}
      }
      render();progress("送信処理終了",done,items.length);
      say(done+"件の処理が終了しました。未送信の写真は画面に残っています。");
      ui.driveLink.href="https://drive.google.com/drive/u/0/folders/"+encodeURIComponent(folderID);
      ui.driveLink.hidden=false;
    }catch(error){say("アップロードを開始できません："+error.message);}
    finally{busy=false;updateButtons();}
  });
  if("serviceWorker" in navigator&&location.protocol==="https:"){
    navigator.serviceWorker.register("./service-worker.js").catch(()=>{});
  }
})();