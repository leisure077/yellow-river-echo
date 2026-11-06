const artAnchors={hangu:[200,260],longmen:[810,270],yellowriver:[190,1220],tieta:[850,1170],qicheng:[180,820]};
const mainArtPoints={'hangu':[200,260],'longmen':[810,270],'emperors':[190,1220],'iron-tower':[850,1170],'qicheng':[180,820],'miaodigou':[160,540],'erlitou':[330,640],'shangdu':[770,650]};
for(const p of mapPOIs){
 const center=artAnchors[p.site];
 if(center&&p.uv){p.x=center[0]+(p.uv[0]-.5)*340;p.y=center[1]+(p.uv[1]-.5)*360;}
 if(mainArtPoints[p.id]){[p.x,p.y]=mainArtPoints[p.id];}
}
