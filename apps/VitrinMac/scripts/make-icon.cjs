const {createRequire}=require('module'),fs=require('fs');
// Draws the app icon and the README icon from site/assets/logo.svg (the site's icons: scripts/site-icons.mjs): node apps/VitrinMac/scripts/make-icon.cjs
const R=require('path').resolve(__dirname,'../../..');
const sharp=createRequire(R+'/packages/render/package.json')('sharp');
const svg=fs.readFileSync(R+'/site/assets/logo.svg','utf8');
const inner=svg.replace(/^[\s\S]*?<\/defs>/,'').replace('</svg>','').replace(/<rect[^>]*\/>/,'');
// The macOS icon grid: an 824 pt body on a 1024 canvas with a soft shadow.
const icon=`<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF9E33"/><stop offset=".55" stop-color="#FA6B61"/><stop offset="1" stop-color="#ED5C9E"/></linearGradient>
<linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".16"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient>
<filter id="d" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="14"/></filter>
</defs>
<rect x="100" y="112" width="824" height="824" rx="186" fill="#000" opacity=".3" filter="url(#d)"/>
<rect x="100" y="100" width="824" height="824" rx="186" fill="url(#g)"/>
<rect x="100" y="100" width="824" height="824" rx="186" fill="url(#s)"/>
<g transform="translate(100 100) scale(12.875)">${inner}</g>
</svg>`;
(async()=>{
 const set=R+'/apps/VitrinMac/VitrinMac/Resources/Assets.xcassets/AppIcon.appiconset/';
 const master=await sharp(Buffer.from(icon),{density:144}).resize(1024,1024).png().toBuffer();
 const sizes=[[16,1],[16,2],[32,1],[32,2],[128,1],[128,2],[256,1],[256,2],[512,1],[512,2]];
 const images=[];
 for(const f of fs.readdirSync(set)) if(f.endsWith('.png')) fs.unlinkSync(set+f);
 for(const [s,k] of sizes){const name=`icon_${s}x${s}${k==2?'@2x':''}.png`;await sharp(master).resize(s*k,s*k).png().toFile(set+name);images.push({idiom:'mac',filename:name,scale:k+'x',size:`${s}x${s}`});}
 fs.writeFileSync(set+'Contents.json',JSON.stringify({images,info:{author:'xcode',version:1}},null,2)+'\n');
 await sharp(master).resize(256,256).png().toFile(R+'/docs/icon.png');
 
 console.log('ok');
})();
