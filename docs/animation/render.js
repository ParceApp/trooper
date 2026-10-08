const puppeteer = require('puppeteer-core');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');

async function renderMinimalAnimation() {
  const outputDir = path.resolve(__dirname);
  const mp4Path = path.join(outputDir, 'trooper_architecture_flow.mp4');
  const gifPath = path.join(outputDir, 'trooper_architecture_flow.gif');

  console.log('🚀 Launching Headless Chrome for minimalist flow render...');
  const browser = await puppeteer.launch({
    executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--force-device-scale-factor=1'
    ]
  });

  const page = await browser.newPage();
  // 860x280 is the clean banner aspect ratio
  await page.setViewport({ width: 880, height: 280, deviceScaleFactor: 1 });

  const htmlUrl = 'file://' + path.join(__dirname, 'index.html');
  console.log(`📄 Loading animation stage: ${htmlUrl}`);
  await page.goto(htmlUrl, { waitUntil: 'networkidle0' });

  // Initialize CDP session for high-fps screencast
  const client = await page.target().createCDPSession();

  console.log('🎬 Starting FFmpeg pipe for MP4 recording...');
  const ffmpeg = spawn('/opt/homebrew/bin/ffmpeg', [
    '-y',
    '-f', 'image2pipe',
    '-vcodec', 'mjpeg',
    '-r', '30',
    '-i', '-',
    '-c:v', 'libx264',
    '-pix_fmt', 'yuv420p',
    '-preset', 'medium',
    '-crf', '18',
    mp4Path
  ]);

  let frameCount = 0;
  client.on('Page.screencastFrame', async ({ data, sessionId }) => {
    frameCount++;
    const buffer = Buffer.from(data, 'base64');
    ffmpeg.stdin.write(buffer);
    await client.send('Page.screencastFrameAck', { sessionId });
  });

  await client.send('Page.startScreencast', {
    format: 'jpeg',
    quality: 95,
    maxWidth: 880,
    maxHeight: 280,
    everyNthFrame: 1
  });

  // Exactly one full cohesive 3-phase cycle
  const recordingDurationSec = 9.8;
  console.log(`⏳ Recording minimal 3-phase architecture flow (${recordingDurationSec}s)...`);
  await new Promise(r => setTimeout(r, recordingDurationSec * 1000));

  console.log('⏹️ Stopping screencast and finalizing MP4...');
  await client.send('Page.stopScreencast');
  await browser.close();

  ffmpeg.stdin.end();

  await new Promise((resolve, reject) => {
    ffmpeg.on('close', code => {
      if (code === 0) {
        console.log(`✅ MP4 rendered successfully: ${mp4Path} (${frameCount} frames)`);
        resolve();
      } else {
        reject(new Error(`FFmpeg exited with code ${code}`));
      }
    });
  });

  // Generate crisp, lightweight GIF
  console.log('🎨 Generating optimized animated GIF via FFmpeg palettegen/paletteuse...');
  await new Promise((resolve, reject) => {
    const gifFfmpeg = spawn('/opt/homebrew/bin/ffmpeg', [
      '-y',
      '-i', mp4Path,
      '-vf', 'fps=20,scale=880:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=96:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3',
      gifPath
    ]);

    gifFfmpeg.on('close', code => {
      if (code === 0) {
        const stats = fs.statSync(gifPath);
        console.log(`✅ GIF generated successfully: ${gifPath} (${(stats.size / 1024).toFixed(1)} KB)`);
        resolve();
      } else {
        reject(new Error(`GIF generation failed with code ${code}`));
      }
    });
  });

  console.log('🎉 Minimalist Trooper Flow animation rendered successfully!');
}

renderMinimalAnimation().catch(err => {
  console.error('❌ Render failed:', err);
  process.exit(1);
});
