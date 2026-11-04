#!/usr/bin/env node
/**
 * 3D 文物工坊 · 第 1 步：离线资产流水线（只写 .tmp，不动 rawfile）
 *
 * 用法（RELIC_SRC 必填，指向六件原始 glb 所在目录）：
 *   RELIC_SRC="D:/gltf-src" node compress_relics.mjs
 *
 * 流程：
 *   舞蹈纹砖   metalrough → quantize → meshopt
 *   双龙耳瓶   去法线+weld → simplify 0.2（目标约 45 万面）→ quantize → meshopt
 *   三彩马     quantize → meshopt
 *   安德森陶罐 quantize → meshopt
 *   青铜方彝   weld → resize 1024 → quantize → meshopt（源件仅 2.7 万面）
 *   青铜镈钟   weld → quantize → meshopt（源件约 40 万面）
 *
 * 注意：双龙耳瓶的 674 万顶点是逐三角拆开的（法线逐面不同），直接 weld 合不动、
 * simplify 也只会削掉 1%。所以先卸掉 NORMAL/TANGENT 再 weld，简化为 45 万面后
 * 在 viewer 里用 toCreasedNormals() 重算法线。产物体积因此不含法线。
 */
import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, writeFileSync, statSync, closeSync, openSync, readSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const ROOT = dirname(fileURLToPath(import.meta.url));
const TOOLS = join(ROOT, '.tmp', 'gltf-tools');
const CLI = join(TOOLS, 'node_modules', '@gltf-transform', 'cli', 'bin', 'cli.js');
// 原始扫描件所在的目录。故意不预设有默认值：这些 glb 只在当初下载它们的那台机器上，
// 写死一个本机路径到别的电脑上只会变成"找不到文件"，不如第一次跑就让人指明。
const SRC = process.env.RELIC_SRC;
if (!SRC) {
  console.error('要指定原始 glb 的目录，例如：\n' +
    '  RELIC_SRC="D:/gltf-src" node compress_relics.mjs\n' +
    '（Windows cmd 下先 set RELIC_SRC=D:/gltf-src 再跑）');
  process.exit(1);
}
const TMP = join(ROOT, '.tmp', 'relics');
const WORK = join(TMP, 'work');
const OUT = join(TMP, 'out');
const REPORT = join(TMP, 'report.json');

const MODELS = [
  {
    id: 'dragon-amphora',
    label: '三彩双龙耳瓶',
    src: 'dragon-handled_amphora.glb',
    out: 'dragon-amphora.glb',
    // 674 万顶点全是拆分点，法线逐面不同；先去 NORMAL/TANGENT 再 weld，
    // 否则 weld 合不动、simplify 只会削掉 1%
    pipeline: [
      { prepare: 'stripNormalsWeld', mid: 'dragon.strip.glb' },
      { cmd: 'simplify', mid: 'dragon.simplify.glb', args: ['--ratio', '0.2', '--error', '1', '--lock-border', 'false'] }
    ]
  },
  {
    id: 'dancer-brick',
    label: '舞蹈纹画像砖',
    src: '1921.263_architectural_brick_with_dancer_in_reli.glb',
    out: 'dancer-brick.glb',
    // r160 的 GLTFLoader 已移除 KHR_materials_pbrSpecularGlossiness，必须先转 metal/rough
    pipeline: [
      { cmd: 'metalrough', mid: 'brick.metalrough.glb' }
    ]
  },
  {
    id: 'sancai-horse',
    label: '三彩马',
    src: 'combo.glb',
    out: 'sancai-horse.glb',
    pipeline: []
  },
  {
    id: 'andersson-vessel',
    label: '安德森藏陶罐',
    src: 'johan_gunnar_andersson_vessel.glb',
    out: 'andersson-vessel.glb',
    pipeline: []
  },
  {
    id: 'fangyi',
    label: '兽面纹青铜方彝',
    src: '804468123a8849108b83944ee1008aa5_normalized_optimized.glb',
    out: 'fangyi.glb',
    // 源件 Draco 压缩、仅 2.7 万面，无法“简化到 30-45 万”；走解码→weld→
    // 贴图降到 1024→quantize→meshopt，体积主要由贴图决定
    pipeline: [
      { cmd: 'weld', mid: 'fangyi.weld.glb' },
      { cmd: 'resize', mid: 'fangyi.resize.glb', args: ['--width', '1024', '--height', '1024'] }
    ]
  },
  {
    id: 'bell',
    label: '青铜镈钟',
    src: 'bronze_bo_bell.glb',
    out: 'bell.glb',
    // 源件已约 40 万面，落在目标区间，不需要 simplify
    pipeline: [
      { cmd: 'weld', mid: 'bell.weld.glb' }
    ]
  }
];

function fail(message) {
  console.error('\n[失败] ' + message);
  process.exit(1);
}

function ensureDir(dir) {
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
}

function mb(bytes) {
  return (bytes / 1048576).toFixed(2) + ' MB';
}

function runCli(args, label) {
  const started = Date.now();
  console.log('\n▶ ' + label);
  console.log('  node ' + CLI + ' ' + args.join(' '));
  const result = spawnSync(process.execPath, [CLI, ...args], {
    stdio: 'inherit',
    env: { ...process.env, NODE_OPTIONS: '--max-old-space-size=4096' }
  });
  if (result.error) {
    throw new Error(label + ' 启动失败：' + result.error.message);
  }
  if (result.status !== 0) {
    throw new Error(label + ' 退出码 ' + result.status);
  }
  console.log('  ✓ ' + ((Date.now() - started) / 1000).toFixed(1) + 's');
}

let sdkModules = null;

async function sdk() {
  if (sdkModules === null) {
    const base = join(TOOLS, 'node_modules', '@gltf-transform');
    sdkModules = {
      core: await import(pathToFileURL(join(base, 'core', 'dist', 'index.js')).href),
      extensions: await import(pathToFileURL(join(base, 'extensions', 'dist', 'index.js')).href),
      functions: await import(pathToFileURL(join(base, 'functions', 'dist', 'index.js')).href)
    };
  }
  return sdkModules;
}

// 扫描件逐面拆点，法线也逐面不同；卸掉法线后 weld 才能把位置相同的点合起来。
// 产物不带 NORMAL，viewer 加载后用 toCreasedNormals() 重算。
async function stripNormalsAndWeld(src, out) {
  const { core, extensions, functions } = await sdk();
  const io = new core.NodeIO().registerExtensions(extensions.ALL_EXTENSIONS);
  const doc = await io.read(src);
  let removed = 0;
  for (const mesh of doc.getRoot().listMeshes()) {
    for (const prim of mesh.listPrimitives()) {
      if (prim.getAttribute('NORMAL')) {
        prim.setAttribute('NORMAL', null);
        removed += 1;
      }
      if (prim.getAttribute('TANGENT')) {
        prim.setAttribute('TANGENT', null);
        removed += 1;
      }
    }
  }
  await doc.transform(functions.weld());
  await io.write(out, doc);
  return removed;
}

// 读 GLB 的 JSON 块统计面数/顶点/扩展。meshopt 只换二进制块，accessor count 不变。
function glbStats(path) {
  const fd = openSync(path, 'r');
  try {
    const head = Buffer.alloc(20);
    readSync(fd, head, 0, 20, 0);
    if (head.readUInt32LE(0) !== 0x46546c67) {
      throw new Error('不是 GLB 文件：' + path);
    }
    const jsonLen = head.readUInt32LE(12);
    const jsonBuf = Buffer.alloc(jsonLen);
    readSync(fd, jsonBuf, 0, jsonLen, 20);
    const gltf = JSON.parse(jsonBuf.toString('utf8').trim());
    let triangles = 0;
    let vertices = 0;
    let primitives = 0;
    let normalPrimitives = 0;
    for (const mesh of gltf.meshes || []) {
      for (const prim of mesh.primitives || []) {
        primitives += 1;
        if (prim.attributes?.NORMAL !== undefined) {
          normalPrimitives += 1;
        }
        const pos = prim.attributes?.POSITION;
        if (pos !== undefined) {
          vertices += gltf.accessors[pos].count;
        }
        if (prim.indices !== undefined) {
          triangles += gltf.accessors[prim.indices].count / 3;
        } else if (pos !== undefined) {
          triangles += gltf.accessors[pos].count / 3;
        }
      }
    }
    return {
      bytes: statSync(path).size,
      triangles: Math.round(triangles),
      vertices,
      primitives,
      normalPrimitives,
      materials: (gltf.materials || []).length,
      extensionsUsed: gltf.extensionsUsed || [],
      extensionsRequired: gltf.extensionsRequired || []
    };
  } finally {
    closeSync(fd);
  }
}

function compactExtensions(list) {
  return list
    .filter((e) => e !== 'KHR_materials_specular' && e !== 'KHR_materials_ior')
    .join(', ') || '—';
}

async function main() {  console.log('3D 文物工坊 · 离线资产流水线');
  console.log('源目录：' + resolve(SRC));
  console.log('输出目录：' + OUT);
  if (!existsSync(CLI)) {
    fail('找不到 gltf-transform CLI。先运行：npm install --prefix .tmp/gltf-tools @gltf-transform/cli@4.5.1');
  }
  ensureDir(WORK);
  ensureDir(OUT);

  const rows = [];
  const failures = [];

  for (const model of MODELS) {
    const srcPath = join(SRC, model.src);
    const outPath = join(OUT, model.out);
    console.log('\n============================================================');
    console.log(model.label + '  ←  ' + model.src);
    if (!existsSync(srcPath)) {
      failures.push({ id: model.id, label: model.label, error: '源文件不存在：' + srcPath });
      console.log('[跳过] 源文件不存在：' + srcPath);
      continue;
    }
    const before = glbStats(srcPath);
    console.log('  源：' + mb(before.bytes) + ' · ' + before.triangles.toLocaleString() + ' 面 · ' +
      before.vertices.toLocaleString() + ' 顶点');

    try {
      const started = Date.now();
      let current = srcPath;

      for (const step of model.pipeline) {
        const next = join(WORK, step.mid);
        if (step.prepare === 'stripNormalsWeld') {
          const started = Date.now();
          console.log('\n▶ 去法线 + weld · ' + model.label);
          const removed = await stripNormalsAndWeld(current, next);
          console.log('  卸掉 NORMAL/TANGENT ' + removed + ' 个，weld 完成；' +
            ((Date.now() - started) / 1000).toFixed(1) + 's');
        } else {
          runCli([step.cmd, current, next, ...(step.args || [])], step.cmd + ' · ' + model.label);
        }
        if (!existsSync(next)) {
          throw new Error(step.prepare || step.cmd + ' 没有产出 ' + next);
        }
        console.log('  中间产物：' + step.mid + ' · ' + mb(statSync(next).size));
        current = next;
      }

      const quantized = join(WORK, model.id + '.quantize.glb');
      runCli(['quantize', current, quantized], 'quantize · ' + model.label);
      console.log('  中间产物：' + model.id + '.quantize.glb · ' + mb(statSync(quantized).size));

      runCli(['meshopt', quantized, outPath], 'meshopt · ' + model.label);
      if (!existsSync(outPath)) {
        throw new Error('meshopt 没有产出 ' + outPath);
      }

      const after = glbStats(outPath);
      const ratio = before.bytes > 0 ? (after.bytes / before.bytes) * 100 : 0;
      rows.push({
        id: model.id,
        label: model.label,
        src: model.src,
        out: outPath,
        sourceBytes: before.bytes,
        sourceTriangles: before.triangles,
        sourceVertices: before.vertices,
        bytes: after.bytes,
        triangles: after.triangles,
        vertices: after.vertices,
        primitives: after.primitives,
        normalPrimitives: after.normalPrimitives,
        materials: after.materials,
        percentOfSource: Number(ratio.toFixed(1)),
        seconds: Number(((Date.now() - started) / 1000).toFixed(1)),
        extensionsUsed: after.extensionsUsed,
        extensionsRequired: after.extensionsRequired
      });
      console.log('  最终：' + mb(after.bytes) + ' · ' + after.triangles.toLocaleString() + ' 面 · ' +
        after.vertices.toLocaleString() + ' 顶点 · 源体积 ' + ratio.toFixed(1) + '%');
    } catch (error) {
      failures.push({ id: model.id, label: model.label, error: error.message });
      console.log('\n[失败] ' + model.label + '：' + error.message);
    }
  }

  const totalSource = rows.reduce((sum, r) => sum + r.sourceBytes, 0) +
    failures.reduce((sum, f) => {
      const model = MODELS.find((m) => m.id === f.id);
      return sum + (model && existsSync(join(SRC, model.src)) ? statSync(join(SRC, model.src)).size : 0);
    }, 0);
  const totalOut = rows.reduce((sum, r) => sum + r.bytes, 0);

  console.log('\n============================================================');
  console.log('结果（全部在 .tmp/relics/out，未写入 rawfile）');
  console.log('');
  console.log('| 文物 | 源体积 | 产物体积 | 压缩到 | 面数 | 顶点 | 法线 | 耗时 |');
  console.log('|---|---|---|---|---|---|---|---|');
  for (const r of rows) {
    console.log('| ' + r.label + ' | ' + mb(r.sourceBytes) + ' | ' + mb(r.bytes) + ' | ' +
      r.percentOfSource + '% | ' + r.triangles.toLocaleString() + ' | ' +
      r.vertices.toLocaleString() + ' | ' + (r.normalPrimitives > 0 ? '保留' : '运行时重算') + ' | ' +
      r.seconds + 's |');
  }
  console.log('');
  console.log('合计：' + mb(totalSource) + ' → ' + mb(totalOut) +
    '（' + (totalOut / totalSource * 100).toFixed(1) + '%）');
  for (const r of rows) {
    console.log('  ' + r.label + ' 扩展：' + compactExtensions(r.extensionsUsed));
  }
  if (failures.length) {
    console.log('\n失败：');
    for (const f of failures) {
      console.log('  - ' + f.label + '：' + f.error);
    }
  }

  writeFileSync(REPORT, JSON.stringify({
    generatedAt: new Date().toISOString(),
    sourceDir: resolve(SRC),
    outputDir: OUT,
    totalSourceBytes: totalSource,
    totalOutputBytes: totalOut,
    models: rows,
    failures
  }, null, 2), 'utf8');
  console.log('\n报告：' + REPORT);
  if (failures.length) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  fail(error.message || String(error));
});
