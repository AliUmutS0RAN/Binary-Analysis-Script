#!/bin/bash

# Gerekli araçları kontrol et
for cmd in file strings objdump readelf ldd gnuplot; do
    if ! command -v $cmd &> /dev/null; then
        echo "$cmd aracı sistemde yüklü değil. Lütfen yükleyin."
        exit 1
    fi
done

# Log dosyasını tanımla
log_dosyasi="analysis_log_$(date +%Y%m%d_%H%M%S).txt"
> "$log_dosyasi"

# Kullanıcıdan analiz edilecek dizini veya dosya adını al
echo "Lütfen analiz edilecek dizini veya dosya adını girin:"
read hedef_dizin

# Girilen yolun var olup olmadığını kontrol et
if [ ! -e "$hedef_dizin" ]; then
    echo "Girilen dosya veya dizin bulunamadı!" | tee -a "$log_dosyasi"
    exit 1
fi

# Rapor dosyasını tanımla ve tarih-saat ekle
rapor_dosyasi="binary_analysis_report_$(date +%Y%m%d_%H%M%S).txt"
> "$rapor_dosyasi" # Eski raporu temizle

# Kullanıcıya yapılacak işlemleri sun
echo "Yapılacak işlemi seçin:"
echo "1. Dosya türünü belirle"
echo "2. Okunabilir metinleri bul ve en çok geçen 10 stringi göster"
echo "3. Disassembly yap"
echo "4. ELF başlıklarını incele"
echo "5. Dinamik bağlantı kütüphanelerini kontrol et"
echo "6. Binary içindeki segmentleri listele ve görselleştir"
read -p "Seçiminiz: " islem_secim

# İşleme süresini kaydet
start_time=$(date +%s)

# Kullanıcının seçimine göre işlem yap
case $islem_secim in
    1)
        for dosya in "$hedef_dizin"/*; do
            echo "Analiz ediliyor: $dosya" | tee -a "$rapor_dosyasi" "$log_dosyasi"
            dosya_turu=$(file "$dosya")
            echo "Dosya türü: $dosya_turu" | tee -a "$rapor_dosyasi" "$log_dosyasi"
            echo "=============================" | tee -a "$rapor_dosyasi" "$log_dosyasi"
        done
        ;;
    2)
        for dosya in "$hedef_dizin"/*; do
            echo "Okunabilir metinler ve string sıklığı analiz ediliyor: $dosya" | tee -a "$rapor_dosyasi" "$log_dosyasi"
            strings "$dosya" | tee -a "strings_output.txt"
            sort strings_output.txt | uniq -c | sort -nr | head -10 | tee -a "$rapor_dosyasi" "$log_dosyasi"
            echo "=============================" | tee -a "$rapor_dosyasi" "$log_dosyasi"
        done
        ;;
    3)
        echo "Disassembly seçildi. Alt seçeneklerden birini seçin:"
        echo "1. Tüm disassembly"
        echo "2. Sadece işaretli fonksiyonlar"
        echo "3. Sadece semboller"
        read -p "Alt seçiminiz: " objdump_secim

        for dosya in "$hedef_dizin"/*; do
            case $objdump_secim in
                1)
                    objdump -d "$dosya" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                    ;;
                2)
                    objdump -D "$dosya" | grep '<' | tee -a "$rapor_dosyasi" "$log_dosyasi"
                    ;;
                3)
                    objdump -t "$dosya" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                    ;;
                *)
                    echo "Geçersiz seçim" | tee -a "$log_dosyasi"
                    ;;
            esac
            echo "=============================" | tee -a "$rapor_dosyasi" "$log_dosyasi"
        done
        ;;
    4)
        for dosya in "$hedef_dizin"/*; do
            dosya_turu=$(file "$dosya")
            if [[ $dosya_turu == *"ELF"* ]]; then
                echo "ELF header analysis for $dosya:" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                readelf -h "$dosya" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                echo "=============================" | tee -a "$rapor_dosyasi" "$log_dosyasi"
            fi
        done
        ;;
    5)
        for dosya in "$hedef_dizin"/*; do
            dosya_turu=$(file "$dosya")
            if [[ $dosya_turu == *"executable"* ]]; then
                echo "Dinamik bağlantı kütüphaneleri for $dosya:" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                ldd "$dosya" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                echo "=============================" | tee -a "$rapor_dosyasi" "$log_dosyasi"
            fi
        done
        ;;
    6)
        for dosya in "$hedef_dizin"/*; do
            if file "$dosya" | grep -q "ELF"; then
                echo "Binary içindeki segmentler tespit ediliyor: $dosya" | tee -a "$rapor_dosyasi" "$log_dosyasi"

                # ELF başlıklarını ve segmentleri incele
                readelf -S "$dosya" | grep -e 'LOAD' -e 'DATA' -e 'CODE' | tee -a "$rapor_dosyasi" "$log_dosyasi"

                # Segmentleri tespit et ve görselleştirme için veri hazırla
                segments=$(readelf -l "$dosya" | grep 'LOAD')
                echo "$segments" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                
                # Segment Boyutlarını Tespit Et
                segment_sizes=$(echo "$segments" | awk '{print $5}')
                echo "$segment_sizes" | tee -a "$rapor_dosyasi" "$log_dosyasi"

                # Anomali tespiti (örneğin, çok büyük segmentler)
                for size in $segment_sizes; do
                    if (( size > 1000000 )); then
                        echo "UYARI: Segment boyutu anormal derecede büyük: $size" | tee -a "$rapor_dosyasi" "$log_dosyasi"
                    fi
                done

                # Segment boyutlarını görselleştirme
                echo "Segment boyutlarını görselleştirme:" | tee -a "$log_dosyasi"
                
                # Görselleştirme için veriyi hazırlama
                graph_data="segment_sizes.dat"
                echo "$segment_sizes" | tr ' ' '\n' > "$graph_data"

                # Gnuplot komut dosyasını oluşturma
                gnuplot_script="plot_segments.gp"
                cat << EOF > $gnuplot_script
set terminal png size 800,600
set output 'segment_sizes.png'
set title "Segment Boyutları"
set xlabel "Segment Numarası"
set ylabel "Boyut (Bytes)"
plot "$graph_data" with linespoints title 'Segment Boyutları'
EOF

                # Grafiği oluşturma
                gnuplot $gnuplot_script

                echo "=============================" | tee -a "$rapor_dosyasi" "$log_dosyasi"
            else
                echo "$dosya bir ELF dosyası değil, atlanıyor." | tee -a "$log_dosyasi"
            fi
        done
        ;;
    *)
        echo "Geçersiz seçim!" | tee -a "$log_dosyasi"
        ;;
esac

end_time=$(date +%s)
elapsed_time=$((end_time - start_time))

echo "İşlem süresi: $elapsed_time saniye" | tee -a "$rapor_dosyasi" "$log_dosyasi"

# İşleme süresini raporun başına yaz
sed -i "1s/^/İşlem süresi: $elapsed_time saniye\n/" "$rapor_dosyasi"

echo "Analiz tamamlandı. Sonuçlar $rapor_dosyasi dosyasına kaydedildi." | tee -a "$log_dosyasi"
