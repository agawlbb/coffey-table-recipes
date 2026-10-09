<?php
declare(strict_types=1);
require_once 'C:/xampp/htdocs/CoffeyTableRecipes/src/RecipeImportTools.php';

/** Development-only importer: download verified image bytes, never serve a proxy. */
final class PhotoArchive
{
    public static function download(string $url, string $directory): array
    {
        $original=$url;
        for($hop=0;$hop<5;$hop++) {
            if(RecipeImportTools::resolveUrl($url,$url)!==$url) throw new RuntimeException('Invalid HTTP image URL');
            $p=parse_url($url); $host=$p['host']; $plain=trim($host,'[]');
            $ips=filter_var($plain,FILTER_VALIDATE_IP)?[$plain]:array_values(array_unique(array_merge(array_column(dns_get_record($plain,DNS_A)?:[],'ip'),array_column(dns_get_record($plain,DNS_AAAA)?:[],'ipv6'))));
            if(!$ips) throw new RuntimeException('DNS lookup failed');
            foreach($ips as $ip) if(!RecipeImportTools::publicIp($ip)) throw new RuntimeException('Non-public image destination rejected');
            $port=$p['port']??($p['scheme']==='https'?443:80);
            $body=''; $location=null; $headerBytes=0; $started=microtime(true);
            $curl=curl_init($url);
            curl_setopt_array($curl,[CURLOPT_PROTOCOLS=>CURLPROTO_HTTP|CURLPROTO_HTTPS,CURLOPT_FOLLOWLOCATION=>false,
                CURLOPT_PROXY=>'',CURLOPT_CONNECTTIMEOUT=>8,CURLOPT_TIMEOUT=>20,CURLOPT_SSL_VERIFYPEER=>true,CURLOPT_SSL_VERIFYHOST=>2,
                CURLOPT_USERAGENT=>'CoffeyTableRecipes/1.0 source-image-verification',CURLOPT_HTTPHEADER=>['Accept: image/*'],
                CURLOPT_RESOLVE=>[$plain.':'.$port.':'.(str_contains($ips[0],':')?'['.$ips[0].']':$ips[0])],
                CURLOPT_HEADERFUNCTION=>static function($c,string $header) use (&$location,&$headerBytes): int {
                    $headerBytes+=strlen($header); if($headerBytes>65536)return 0;
                    if(stripos($header,'location:')===0)$location=trim(substr($header,9)); return strlen($header);
                },
                CURLOPT_WRITEFUNCTION=>static function($c,string $chunk) use (&$body,$started): int {
                    if(strlen($body)+strlen($chunk)>8*1024*1024 || microtime(true)-$started>20)return 0;
                    $body.=$chunk; return strlen($chunk);
                }]);
            $ok=curl_exec($curl); $status=(int)curl_getinfo($curl,CURLINFO_RESPONSE_CODE);
            $type=strtolower(trim(explode(';',(string)curl_getinfo($curl,CURLINFO_CONTENT_TYPE))[0])); $error=curl_error($curl); curl_close($curl);
            if($ok===false)throw new RuntimeException('Image fetch failed: '.$error);
            if(in_array($status,[301,302,303,307,308],true)) {
                $next=$location?RecipeImportTools::resolveUrl($location,$url):null; if(!$next)throw new RuntimeException('Invalid image redirect'); $url=$next; continue;
            }
            if($status!==200 || !str_starts_with($type,'image/'))throw new RuntimeException('Image unavailable (HTTP '.$status.', '.$type.')');
            $info=@getimagesizefromstring($body);
            if(!$info || ($info['mime']??null)!==$type || !in_array($type,['image/jpeg','image/png','image/webp','image/gif'],true)) throw new RuntimeException('Invalid or unsupported image bytes');
            if (!is_dir($directory)) throw new RuntimeException('Archive directory does not exist');
            $extension=['image/jpeg'=>'jpg','image/png'=>'png','image/webp'=>'webp','image/gif'=>'gif'][$type];
            $digest=hash('sha256',$body);
            $filename=$digest.'.'.$extension;
            $path=$directory.DIRECTORY_SEPARATOR.$filename;
            if (is_file($path) && hash_file('sha256',$path)!==$digest) throw new RuntimeException('Archive file conflict');
            if (!is_file($path) && file_put_contents($path,$body,LOCK_EX)!==strlen($body)) throw new RuntimeException('Could not save image');
            return ['source_url'=>$original,'verified_final_url'=>$url,'mime_type'=>$type,'width_pixels'=>$info[0],'height_pixels'=>$info[1],'verified_at_utc'=>gmdate('c'),'sha256'=>$digest,'filename'=>$filename,'bytes'=>strlen($body)];
        }
        throw new RuntimeException('Too many image redirects');
    }

}
