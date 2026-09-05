"""Compose verified figures and an actual window recording; preserve their labels."""
from pathlib import Path
import json,re,subprocess,wave
root=Path(__file__).resolve().parents[1];media=root/'media';work=root/'build/media';work.mkdir(parents=True,exist_ok=True)
segments=json.loads((media/'narration.json').read_text(encoding='utf-8'))
concat=[];timing=[];subtitles=[];offset=0
def timestamp(seconds):
 ms=round(seconds*1000);seconds,ms=divmod(ms,1000);minutes,seconds=divmod(seconds,60);hours,minutes=divmod(minutes,60)
 return f'{hours:02d}:{minutes:02d}:{seconds:02d},{ms:03d}'
for s in segments:
 audio=work/(s['name']+'.wav')
 with wave.open(str(audio),'rb') as w:spoken=w.getnframes()/w.getframerate()
 speed=max(1,spoken/(s['duration']-.5))
 if speed>1.4:raise RuntimeError(f"Narration too long: {s['name']} speed={speed}")
 sentences=re.findall(r'[^。！？]+[。！？]?',s['text'])
 letters=sum(map(len,sentences));cursor=offset
 for sentence in sentences:
  end=cursor+(spoken/speed)*len(sentence)/letters
  subtitles.append(f'{len(subtitles)+1}\n{timestamp(cursor)} --> {timestamp(end)}\n{sentence}\n')
  cursor=end
 output=work/(s['name']+'.mp4')
 input_args=['-loop','1','-framerate','30','-i',str(media/s['image'])] if 'image' in s else ['-i',str(media/s['video'])]
 cmd=['ffmpeg','-hide_banner','-loglevel','error',*input_args,'-i',str(audio),'-filter_complex',f'[1:a]atempo={speed:.6f},apad,atrim=duration={s["duration"]}[voice]',
      '-map','0:v:0','-map','[voice]','-t',str(s['duration']),'-vf','scale=1920:1080,setsar=1','-r','30','-c:v','libx264','-preset','fast','-crf','19','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-ar','48000','-ac','2','-y',str(output)]
 subprocess.run(cmd,check=True,timeout=180)
 concat.append("file '"+output.as_posix()+"'")
 timing.append({'name':s['name'],'start':offset,'end':offset+s['duration'],'source':'actual FPGA UART window capture' if 'video' in s else 'original teaching figure','narration_source':'local Microsoft Huihui SAPI','narration_speed':speed})
 offset+=s['duration']
(work/'concat.txt').write_text('\n'.join(concat)+'\n')
(media/'mips-cpu-demo.srt').write_text('\n'.join(subtitles)+'\n',encoding='utf-8')
subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','concat','-safe','0','-i',str(work/'concat.txt'),'-i',str(media/'mips-cpu-demo.srt'),'-map','0:v','-map','0:a','-map','1:s','-c:v','copy','-c:a','copy','-c:s','mov_text','-metadata:s:s:0','language=zho','-disposition:s:0','default','-movflags','+faststart','-y',str(media/'mips-cpu-demo.mp4')],check=True,timeout=60)
(media/'demo-chapters.json').write_text(json.dumps(timing,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'PASS COMPOSED_DEMO seconds={offset} chapters={len(segments)}')
