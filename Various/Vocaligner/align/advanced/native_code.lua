-- @noindex
-- Numeric kernel only. Lua owns source reads, work/memory limits, cancellation,
-- constraints, confidence, planning and every project mutation.
return [[
function clip(x,a,b) (min(b,max(a,x)););
function quant(x) (x>=INF ? INF : floor(x/quantum+.5););
function wins(c,g,d,bc,bg,bd) (c<bc || (c==bc && (g<bg || (g==bg && d<bd))););
function distance(a,b,ai,bj) local(k,v,spec,cep,delta,rs,rc,ro,re,rp,W,c,context,cl,on,dd,af,bf) (
 af=a[14];bf=b[14];qval=0;
 (af&1)!=0 || (bf&1)!=0 ? INF : a[3]>=.90 && b[3]>=.90 ? silence_cost : (
  spec=0;k=0;loop(32,spec+=a[15+k]*b[15+k];k+=1;);spec=clip((1-spec)/2,0,1);
  cep=0;k=0;loop(12,v=(a[47+k]-b[47+k])/2;cep+=min(v*v,1)/12;k+=1;);
  (af&2)!=0 && (bf&2)!=0 ? (delta=0;k=0;loop(6,v=(a[59+k]-b[59+k])/.5;delta+=min(v*v,1)/6;k+=1;);cep=.70*cep+.30*delta;);
  rs=a[6]*b[6];rc=a[7]*b[7];
  context=ai>1 && ai<nd && bj>1 && bj<nr;
  context ? context=!(a[-65+14]&1) && !(a[65+14]&1) && !(b[-65+14]&1) && !(b[65+14]&1);
  ro=a[8]*b[8]*(context ? 1 : .70);re=a[9]*b[9];rp=a[10]*b[10];
  W=w1*rs+w2*rc+w3*ro+w4*re+w5*rp;
  c=w1*rs*spec+w2*rc*cep+w3*ro*abs(a[4]-b[4])+w4*re*abs(a[5]-b[5]);
  w5>0 && rp>0 && (af&16)!=0 && (bf&16)!=0 ? (
   dd=min(abs(a[12]-b[12])/3,1);
   (af&32)!=0 && (bf&32)!=0 ? dd=.75*dd+.25*min(abs(a[13]-b[13])/2,1);
   c+=w5*rp*dd;
  );
  qval=W/wfull;c=qval>=min_pair ? c/W : unknown_cost;
  cl=.65*(a[2]*b[3]+a[3]*b[2]);
  (af&4)!=0 && (bf&4)!=0 ? cl+=.10*abs(a[11]-b[11])*(1-a[3])*(1-b[3]);
  on=context ? .12*max(a[4],b[4])*(abs(a[-65+4]-b[-65+4])+abs(a[65+4]-b[65+4]))/2 : 0;
  clip(c+missing_penalty*(1-qval)+cl+on,0,max_cost);
 );
);
function pair(ii,jj) local(meta,ai,a,b,ci,cachemeta,cell,c) (
 qval=0;c=INF;
 ii>=1 && ii<=N ? (
  meta=regions+(ii-1)*5;
  jj>=meta[0] && jj<=meta[1] ? (
   ai=first+ii-1;a=dframes+(ai-1)*65;b=rframes+(jj-1)*65;
   cell=meta[2]+jj-meta[0];
   !(has_mask && masks[cell]) && !(has_forbidden && abs(a[0]-forbidden_dub)<=forbidden_dr && abs(refpos+b[0]-forbidden_ref)<=forbidden_rr) ? (
    override ? (c=overrides[cell*2];qval=overrides[cell*2+1];) : (
     ci=-1;
     has_cache ? (
      cachemeta=cache_rows+(ai-1)*3;
      jj>=cachemeta[0] && jj<=cachemeta[1] ? ci=cachemeta[2]+jj-cachemeta[0];
     );
     ci>=0 && pair_q[ci]>=0 ? (c=pair_c[ci];qval=pair_q[ci];cache_hits+=1;) : (
      c=distance(a,b,ai,jj);
      ci>=0 && c<INF ? (pair_c[ci]=c;pair_q[ci]=qval;cache_entries+=1;);
     );
    );
   );
  );
 );c;
);
function boundary(ii,jj) local(c,q,before,after) (
 c=pair(ii,jj);q=qval;
 q<.65 || c>.30 ? 0 : (before=pair(ii-1,jj-1);after=pair(ii+1,jj+1);(before+c+after)/3<=.40;);
);
function fetch(ptr,lo,hi,jj,s) local(p) (
 gc=INF;gg=0;gd=0;
 jj>=lo && jj<=hi ? (p=ptr+(jj-lo)*RS+(s-1)*3;gc=p[0];gc<INF ? (gg=p[1];gd=p[2];););
 gc;
);
function fetchgap(ptr,lo,hi,jj,which) local(p) (
 gc=INF;gg=0;gd=0;gp=0;
 jj>=lo && jj<=hi ? (p=ptr+(jj-lo)*RS+S*3+which*4;gc=p[0];gc<INF ? (gg=p[1];gd=p[2];gp=p[3];););
 gc;
);
function slope(s,ii,jj) local(di,dj,k,am,bm) (
 di=s==3 ? 2 : 1;dj=s==2 ? 2 : 1;
 ii-di+1<1 || jj-dj+1<1 ? beta : (
  am=0;bm=0;k=ii-di+1;loop(di,am+=dframes[(first+k-2)*65+1];k+=1;);
  k=jj-dj+1;loop(dj,bm+=rframes[(k-1)*65+1];k+=1;);bm/am;
 );
);
function edge(ii,jj,s) local(a,b,c,prev,cc,am,bm,offset,ac,disp,sigma,prior) (
 a=dframes+(first+ii-2)*65;b=rframes+(jj-1)*65;c=pair(ii,jj);edge_ok=c<INF;
 edge_ok ? (
  offset=dubpos-refpos;am=a[1];bm=b[1];ac=a[1]*c;disp=floor(abs(offset+(a[0]-b[0]))/.00001+.5);
  s==2 ? (
   jj<2 ? edge_ok=0 : (
    prev=b-65;cc=pair(ii,jj-1);edge_ok=cc<INF;
    bm+=prev[1];ac=a[1]*(prev[1]*cc+b[1]*c)/bm;
    disp=floor((abs(offset+(a[0]-prev[0]))*prev[1]+abs(offset+(a[0]-b[0]))*b[1])/bm/.00001+.5);
   );
  ) : s==3 ? (
   ii<2 ? edge_ok=0 : (
    prev=a-65;cc=pair(ii-1,jj);edge_ok=cc<INF;
    am+=prev[1];ac+=prev[1]*cc;disp+=floor(abs(offset+(prev[0]-b[0]))/.00001+.5);
   );
  );
  sigma=bm/am;prior=.025*am*min(4,log(sigma/beta)^2)+.018*am*abs(-offset+(b[0]-a[0]))/search_s;
  eac=ac;emass=am;esigma=sigma;eprior=prior;edisp=disp;
 );
);
function put(s,c,g,d,p) local(at,word,mult) (
 c<INF ? (
  c>=9007199254740992 ? overflow=1;
  at=cellptr+(s-1)*3;at[0]=c;at[1]=g;at[2]=d;
  word=floor((s-1)/6);mult=256^((s-1)%6);trace[cellindex*words+word]+=p*mult;
 );
);
function tracebyte(s,p) local(word,mult) (
 word=floor((s-1)/6);mult=256^((s-1)%6);trace[cellindex*words+word]+=p*mult;
);
function macro_d() local(meta,count,e,origin,slot,price,len,k,pc,pg,pd,p,bc,bg,bd,bp,be,hm) (
 meta=dmacro+(i-1)*13;count=meta[0];bc=INF;bg=INF;bd=INF;bp=0;be=0;e=1;
 loop(count,
  origin=meta[e*4-3];slot=meta[e*4-2];price=meta[e*4-1];len=meta[e*4];
  slot>=0 && boundary(origin,j) ? (
   hm=regions+(origin-1)*5;
   j>=hm[0] && j<=hm[1] ? (
    p=history+slot*history_stride+(j-hm[0])*9;k=1;
    loop(3,
     pc=p[(k-1)*3];pg=p[(k-1)*3+1];pd=p[(k-1)*3+2];
     pc<INF && wins(pc+price,pg+len,pd,bc,bg,bd) ? (bc=pc+price;bg=pg+len;bd=pd;bp=k;be=e;);
     k+=1;
    );
   );
  );e+=1;
 );put(DM,bc,bg,bd,bp);tracebyte(S+1,be);
);
function macro_r() local(meta,count,e,origin,price,len,k,bc,bg,bd,bp,be) (
 meta=rmacro+(j-1)*10;count=meta[0];bc=INF;bg=INF;bd=INF;bp=0;be=0;e=1;
 loop(count,
  origin=meta[e*3-2];price=meta[e*3-1];len=meta[e*3];
  price<INF && boundary(i,origin) ? (
   k=1;loop(3,
    fetch(row,rowlo,rowhi,origin,k);
    gc<INF && wins(gc+price,gg+len,gd,bc,bg,bd) ? (bc=gc+price;bg=gg+len;bd=gd;bp=k;be=e;);
    k+=1;
   );
  );e+=1;
 );put(RM,bc,bg,bd,bp);tracebyte(S+2,be);
);
function summarize(which,a,b) local(k,p,bc,bg,bd,bp) (
 bc=INF;bg=INF;bd=INF;bp=0;k=a;
 loop(max(0,b-a+1),p=cellptr+(k-1)*3;
  p[0]<INF && wins(p[0],p[1],p[2],bc,bg,bd) ? (bc=p[0];bg=p[1];bd=p[2];bp=k;);k+=1;
 );
 p=cellptr+S*3+which*4;
 p[0]=bc;p[1]=bg;p[2]=bd;p[3]=bp;
);
function beginrow() local(meta,k,p,n) (
 meta=regions+(i-1)*5;rowlo=meta[0];rowhi=meta[1];j=rowlo;
 row=rolling+((i-1)%3)*row_stride;
 prev=rolling+((i+1)%3)*row_stride;prev2=rolling+(i%3)*row_stride;
 prevlo=1;prevhi=0;prev2lo=1;prev2hi=0;
 i>1 ? (prevlo=regions[(i-2)*5];prevhi=regions[(i-2)*5+1];);
 i>2 ? (prev2lo=regions[(i-3)*5];prev2hi=regions[(i-3)*5+1];);
 n=max(0,rowhi-rowlo+1);k=0;
 loop(n,
  p=row+k*RS;memset(p,INF,RS);k+=1;
 );
);
mode==0 ? (
 cache_hits=0;cache_entries=0;has_cache ? memset(pair_q,-1,cache_count);
) : mode==1 ? (
 i=1;done=0;visited=0;states_visited=0;overflow=0;
 memset(trace,0,total_cells*words);macro_enabled ? memset(history,INF,history_size);
 beginrow();
) : mode==2 ? (
 block=0;
 while(block<block_cells && !done && !overflow)(
  j>rowhi ? (
   i+=1;i>N ? done=1 : beginrow();
  ) : (
   cellindex=regions[(i-1)*5+2]+j-rowlo;cellptr=row+(j-rowlo)*RS;
   state=1;
   loop(3,
    di=state==3 ? 2 : 1;dj=state==2 ? 2 : 1;pi=i-di;pj=j-dj;
    edge(i,j,state);
    edge_ok ? (
     bc=INF;bg=INF;bd=INF;bp=0;
     pi==0 && pj>=0 ? (
      startj=j-dj+1;dist=abs(rframes[(startj-1)*65]-guide_start);
      dist<=.08000001 ? (bc=quant(eac+(eprior+.025*A*dist/.080));bg=0;bd=edisp;bp=254;);
     );
     pp=di==2 ? prev2 : prev;plo=di==2 ? prev2lo : prevlo;phi=di==2 ? prev2hi : prevhi;
     ps=1;loop(3,
      fetch(pp,plo,phi,pj,ps);
      gc<INF ? (
       extra=.020*emass*min(4,log(esigma/slope(ps,pi,pj))^2);
       c=gc+quant(eac+(eprior+extra));d=gd+edisp;
       wins(c,gg,d,bc,bg,bd) ? (bc=c;bg=gg;bd=d;bp=ps;);
      );ps+=1;
     );
     closeprice=quant(eac+(eprior+gap_close));fetchgap(pp,plo,phi,pj,0);
     gc<INF ? (c=gc+closeprice;d=gd+edisp;wins(c,gg,d,bc,bg,bd) ? (bc=c;bg=gg;bd=d;bp=gp;););
     macro_enabled ? (
      fetchgap(pp,plo,phi,pj,1);pc=gc;pg=gg;pd=gd;pred=gp;
      pc<INF && boundary(i-di+1,j-dj+1) ? (c=pc+closeprice;d=pd+edisp;wins(c,pg,d,bc,bg,bd) ? (bc=c;bg=pg;bd=d;bp=pred;););
     );
     put(state,bc,bg,bd,bp);
    );state+=1;
   );
   side=1;loop(2,
    isdub=side==1;off=isdub ? 3 : 3+G;pp=isdub ? prev : row;plo=isdub ? prevlo : rowlo;phi=isdub ? prevhi : rowhi;
    pj=isdub ? j : j-1;idx=isdub ? first+i-2 : j-1;cap=isdub ? dmax[idx] : rmax[idx];len=1;
    loop(cap,
     bc=INF;bg=INF;bd=INF;bp=0;
     len==1 ? (
      ps=1;loop(3,
       fetch(pp,plo,phi,pj,ps);c=gc+(isdub ? dopen[idx] : ropen[idx]);
       wins(c,gg+1,gd,bc,bg,bd) ? (bc=c;bg=gg+1;bd=gd;bp=ps;);ps+=1;
      );
     ) : (
      fetch(pp,plo,phi,pj,off+len-1);bc=gc+(isdub ? dstep[idx] : rstep[idx]);bg=gg+1;bd=gd;bp=off+len-1;
     );
     put(off+len,bc,bg,bd,bp);len+=1;
    );side+=1;
   );
   macro_enabled ? (macro_d();macro_r(););
   summarize(0,4,3+2*G);macro_enabled ? summarize(1,DM,RM);
   slot=regions[(i-1)*5+4];
   macro_enabled && slot>=0 ? (
    hp=history+slot*history_stride+(j-rowlo)*9;memcpy(hp,cellptr,9);
   );
   visited+=1;states_visited+=3+dmax[first+i-2]+rmax[j-1]+(macro_enabled ? 2 : 0);
   j+=1;block+=1;
  );
 );
);
]]
