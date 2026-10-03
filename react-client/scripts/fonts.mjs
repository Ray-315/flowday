import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import wawoff2 from 'wawoff2';

const output = new URL('../src/fonts/', import.meta.url);
await mkdir(output, { recursive: true });
for (const weight of ['Regular', 'Medium', 'Bold']) {
  const source = new URL(`../../assets/fonts/HarmonyOS_Sans_SC_${weight}.ttf`, import.meta.url);
  const target = new URL(`HarmonyOS_Sans_SC_${weight}.woff2`, output);
  const compressed = await wawoff2.compress(await readFile(source));
  await writeFile(target, compressed);
  console.log(`${fileURLToPath(target)}: ${(compressed.length / 1024 / 1024).toFixed(2)} MB`);
}
