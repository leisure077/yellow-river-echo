export interface Relic {
  id: string;
  name: string;
  cat: string;
  era: string;
  palette: string;
  shape: string;
  img: string;
  material: string;
  hold: string;
  desc: string;
}

export interface ColorSeed {
  key: string;
  name: string;
}

export const RELIC_CATS: string[] = ['陶瓷', '铜器', '玉石器', '金属器', '书画', '碑帖', '砖瓦', '造像', '文房', '骨角器'];

export const RELIC_ERAS: string[] = ['新石器时代', '夏', '商', '西周', '春秋', '战国', '秦', '汉', '唐', '宋', '元', '明', '清'];

export const RELIC_COLORS: ColorSeed[] = [
  { key: 'yangshao', name: '红陶' },
  { key: 'longshan', name: '玄黑' },
  { key: 'xiashang', name: '青绿' },
  { key: 'zhou', name: '玉色' },
  { key: 'hantang', name: '赭黄' },
  { key: 'song', name: '天青' }
];

const RELICS: Relic[] = [
  { id: 'rl01', name: '人面鱼纹彩陶盆', cat: '陶瓷', era: '新石器时代', palette: 'yangshao', shape: 'pot',
    img: 'relics/rl01.jpg', material: '泥质红陶', hold: '中国国家博物馆',
    desc: '仰韶文化半坡类型的彩陶盆，内壁以黑彩绘出人面与鱼纹相叠，是这类彩陶里最有名的一件。' },
  { id: 'rl02', name: '鹰形陶鼎', cat: '陶瓷', era: '新石器时代', palette: 'yangshao', shape: 'pot',
    img: 'relics/rl02.jpg', material: '夹砂黄陶', hold: '中国国家博物馆',
    desc: '把整只鹰塑成器身：双足与尾撑地成三足，张开的口正好作鼎口，仰韶文化的象形陶器。' },
  { id: 'rl03', name: '红陶兽形壶', cat: '陶瓷', era: '新石器时代', palette: 'yangshao', shape: 'jar',
    img: 'relics/rl03.jpg', material: '夹砂红陶', hold: '山东博物馆',
    desc: '大汶口文化的盛水器，塑成伏立的兽形，四足撑地，背上开注水口，尾端作流。' },
  { id: 'rl04', name: '蛋壳黑陶高柄杯', cat: '陶瓷', era: '新石器时代', palette: 'longshan', shape: 'pot',
    img: 'relics/rl04.jpg', material: '渗碳黑陶', hold: '山东博物馆',
    desc: '龙山文化黑陶的薄胎一路，器壁薄到透光，通体打磨得黑里发亮。' },
  { id: 'rl05', name: '贾湖骨笛', cat: '骨角器', era: '新石器时代', palette: 'hantang', shape: 'box',
    img: 'relics/rl05.jpg', material: '鹤类尺骨', hold: '河南博物院',
    desc: '以鹤的尺骨钻孔制成，孔位旁还能看出当时计算的痕迹，是能吹出音阶的早期管乐器。' },
  { id: 'rl06', name: '镶嵌绿松石兽面纹铜牌饰', cat: '铜器', era: '夏', palette: 'xiashang', shape: 'box',
    img: 'relics/rl06.jpg', material: '青铜嵌绿松石', hold: '河南偃师二里头遗址出土',
    desc: '青铜牌面上逐片嵌粘绿松石，拼出兽面的眼与纹，是二里头文化牌饰的典型做法。' },
  { id: 'rl07', name: '乳钉纹铜爵', cat: '铜器', era: '夏', palette: 'xiashang', shape: 'ding',
    img: 'relics/rl07.jpg', material: '青铜', hold: '河南偃师二里头遗址出土',
    desc: '长流尖尾、细腰三足，腹壁一排乳钉与几道弦纹，是早期青铜礼器的常见格局。' },
  { id: 'rl08', name: '后母戊鼎', cat: '铜器', era: '商', palette: 'xiashang', shape: 'ding',
    img: 'relics/rl08.jpg', material: '青铜', hold: '中国国家博物馆',
    desc: '方腹四足、双耳直立的祭祀大鼎，腹内壁铸出「后母戊」字样族铭，是现存最重的青铜容器。' },
  { id: 'rl09', name: '妇好墓青铜鸮尊', cat: '铜器', era: '商', palette: 'xiashang', shape: 'ding',
    img: 'relics/rl09.jpg', material: '青铜', hold: '河南博物院',
    desc: '两只成对，立鸮作形，鸮首后脑即器口，通体满布鸟纹、兽面纹与蝉纹。' },
  { id: 'rl10', name: '大克鼎', cat: '铜器', era: '西周', palette: 'xiashang', shape: 'ding',
    img: 'relics/rl10.jpg', material: '青铜', hold: '上海博物馆',
    desc: '圆腹双立耳，腹部环饰一周波曲纹，铭文记述克受周王赏赐的经过。' },
  { id: 'rl11', name: '玉柄铁剑', cat: '玉石器', era: '西周', palette: 'zhou', shape: 'box',
    img: 'relics/rl11.jpg', material: '玉柄铁刃', hold: '河南博物院',
    desc: '剑柄用玉、刃部是人工冶铁，玉与铁接铸在一柄之上，三门峡虢国墓出土。' },
  { id: 'rl12', name: '莲鹤方壶', cat: '铜器', era: '春秋', palette: 'zhou', shape: 'jar',
    img: 'relics/rl12.jpg', material: '青铜', hold: '河南博物院',
    desc: '壶盖做成双层莲瓣，中立一只展翅的鹤，肩角攀着兽形，圈足下还有两只伏兽。' },
  { id: 'rl13', name: '云纹铜禁', cat: '铜器', era: '春秋', palette: 'xiashang', shape: 'box',
    img: 'relics/rl13.jpg', material: '青铜', hold: '河南博物院',
    desc: '承放酒器的案形器，四壁由一层层透雕云纹铜梗盘结而成，用的是失蜡法铸造。' },
  { id: 'rl14', name: '曾侯乙编钟', cat: '铜器', era: '战国', palette: 'zhou', shape: 'ding',
    img: 'relics/rl14.jpg', material: '青铜', hold: '湖北省博物馆',
    desc: '合瓦形钟大小成列悬挂，一枚钟能敲出两个音，钟体铸有记音与律名的铭文。' },
  { id: 'rl15', name: '错金银铜版兆域图', cat: '金属器', era: '战国', palette: 'hantang', shape: 'coin',
    img: 'relics/rl15.jpg', material: '青铜错金银', hold: '河北博物院',
    desc: '把王陵的平面缩铸在铜版上，再错出金银线走向与尺寸注记，是现存很早的平面规划图。' },
  { id: 'rl16', name: '秦陵铜车马', cat: '金属器', era: '秦', palette: 'zhou', shape: 'box',
    img: 'relics/rl16.jpg', material: '青铜鎏金', hold: '秦始皇帝陵博物院',
    desc: '按真实车马约一半的比例铸成，车舆、缰绳与御官俑一应俱全，金属件上还留着彩绘。' },
  { id: 'rl17', name: '清明上河图', cat: '书画', era: '宋', palette: 'hantang', shape: 'scroll',
    img: 'relics/rl17.jpg', material: '绢本设色', hold: '故宫博物院',
    desc: '张择端画的汴京河道长卷，从郊外一路画到城门口，桥上船里尽是往来的人。' },
  { id: 'rl18', name: '长信宫灯', cat: '金属器', era: '汉', palette: 'hantang', shape: 'box',
    img: 'relics/rl18.jpg', material: '青铜鎏金', hold: '河北博物院',
    desc: '宫女跪坐执灯的样式，袖口通连体内，点灯时烟被导入腹中，灯盘还能转动调光。' },
  { id: 'rl19', name: '刘胜金缕玉衣', cat: '玉石器', era: '汉', palette: 'zhou', shape: 'box',
    img: 'relics/rl19.jpg', material: '玉片金丝', hold: '河北博物院',
    desc: '上千片玉以金丝编缀成人形殓服，头、衣、手套、鞋分作几段合起来。' },
  { id: 'rl20', name: '弋射收获画像砖', cat: '砖瓦', era: '汉', palette: 'hantang', shape: 'tile',
    img: 'relics/rl20.jpg', material: '灰陶', hold: '中国国家博物馆',
    desc: '一块砖面分上下两栏，上为张弓弋射、下为持镰收割，是汉墓砖上的生产场景。' },
  { id: 'rl21', name: '三彩黑釉马', cat: '陶瓷', era: '唐', palette: 'longshan', shape: 'jar',
    img: 'relics/rl21.jpg', material: '铅釉陶', hold: '洛阳博物馆',
    desc: '白陶胎上大面积施黑釉，只留鬃、蹄与鞍点褐黄，唐三彩里黑釉一路少见。' },
  { id: 'rl22', name: '三彩载乐骆驼俑', cat: '陶瓷', era: '唐', palette: 'hantang', shape: 'pot',
    img: 'relics/rl22.jpg', material: '铅釉陶', hold: '中国国家博物馆',
    desc: '双峰驼背上铺毯，毯上围坐一组奏乐与歌唱的俑，釉色顺着毛势往下流。' },
  { id: 'rl23', name: '龙门石窟卢舍那大佛', cat: '造像', era: '唐', palette: 'xiashang', shape: 'cave',
    img: 'relics/rl23.jpg', material: '石灰岩', hold: '河南洛阳龙门石窟奉先寺',
    desc: '依山崖凿出的坐佛，面部与衣纹整石雕成，两侧弟子、菩萨与力士依次排开。' },
  { id: 'rl24', name: '武则天金简', cat: '金属器', era: '唐', palette: 'hantang', shape: 'stele',
    img: 'relics/rl24.jpg', material: '金', hold: '河南博物院',
    desc: '金叶上双钩刻出字，内容是请求三官上帝除罪祈福，与武周时期的道教信仰有关。' },
  { id: 'rl25', name: '汝窑天青釉洗', cat: '陶瓷', era: '宋', palette: 'song', shape: 'pot',
    img: 'relics/rl25.jpg', material: '青瓷', hold: '宋代汝窑传世器',
    desc: '釉色取"雨过天青"一路，器底留着几枚支钉烧痕，汝窑传世品本就不多。' },
  { id: 'rl26', name: '摹顾恺之洛神赋图', cat: '书画', era: '宋', palette: 'hantang', shape: 'scroll',
    img: 'relics/rl26.jpg', material: '绢本设色', hold: '故宫博物院',
    desc: '按曹植《洛神赋》一段一段画下来的长卷，山水云气作背景，现存的是宋人摹本。' },
  { id: 'rl27', name: '淳化阁帖宋拓本', cat: '碑帖', era: '宋', palette: 'longshan', shape: 'stele',
    img: 'relics/rl27.jpg', material: '纸本墨拓', hold: '上海博物馆',
    desc: '宋代把历代书迹上石汇刻再逐张拓下装订成册，帝王与名家书都在其中，是法帖的祖本一路。' },
  { id: 'rl28', name: '青花釉里红镂雕开光盖罐', cat: '陶瓷', era: '元', palette: 'song', shape: 'jar',
    img: 'relics/rl28.jpg', material: '青花釉里红', hold: '河北博物院',
    desc: '同一器上并用钴料青花与铜红釉里红，腹部镂雕出开光，红与蓝在火里各自发色。' },
  { id: 'rl29', name: '青花缠枝莲纹压手杯', cat: '陶瓷', era: '明', palette: 'song', shape: 'pot',
    img: 'relics/rl29.jpg', material: '青花瓷', hold: '故宫博物院',
    desc: '口沿厚实、握在手里压得住，杯内壁画缠枝莲，明永乐官窑的经典杯形。' },
  { id: 'rl30', name: '田黄三联玺', cat: '文房', era: '清', palette: 'zhou', shape: 'box',
    img: 'relics/rl30.jpg', material: '田黄石', hold: '故宫博物院',
    desc: '一块田黄石雕成相连的三方小玺，石色蜜黄，印文分刻「乾隆宸翰」「乐天」「惟精惟一」。' }
];

export class RelicRepo {
  private static readonly inst: RelicRepo = new RelicRepo();
  static get(): RelicRepo {
    return RelicRepo.inst;
  }

  relics: Relic[] = RELICS;

  byId(id: string): Relic | undefined {
    return this.relics.find((r: Relic): boolean => r.id === id);
  }

  colorName(key: string): string {
    let c = RELIC_COLORS.find((x: ColorSeed): boolean => x.key === key);
    return c === undefined ? key : c.name;
  }

  filtered(kw: string, cats: string[], eras: string[], colors: string[]): Relic[] {
    let k = kw.trim();
    return this.relics.filter((r: Relic): boolean => {
      if (cats.length > 0 && cats.indexOf(r.cat) < 0) {
        return false;
      }
      if (eras.length > 0 && eras.indexOf(r.era) < 0) {
        return false;
      }
      if (colors.length > 0 && colors.indexOf(r.palette) < 0) {
        return false;
      }
      if (k.length === 0) {
        return true;
      }
      return r.name.indexOf(k) >= 0 || r.material.indexOf(k) >= 0 ||
        r.cat.indexOf(k) >= 0 || r.era.indexOf(k) >= 0 || r.desc.indexOf(k) >= 0;
    });
  }
}
