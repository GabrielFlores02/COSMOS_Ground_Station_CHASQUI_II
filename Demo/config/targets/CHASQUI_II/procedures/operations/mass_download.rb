# ============================================================================
# SCRIPT 6: DESCARGA MASIVA
# ============================================================================
# Archivo: procedures/operations/mass_download.rb

load_utility 'ground_station_library'

def mass_data_download
  puts "="*70
  puts "DESCARGA MASIVA DE DATOS"
  puts "="*70
  
  total_downloaded = 0
  
  # Solicitar información de memoria
  puts "\n[STEP 1/4] Consultando estado de memoria..."
  cmd("CHASQUI_II ISSUEPACKET with PACKET DynamicPar, STREAM DEBUG")
  wait(3)
  
  # Leer punteros de todas las particiones
  beacon_write = tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[0]")
  beacon_read = tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[0]")
  beacon_avail = beacon_write - beacon_read
  
  pl_write = tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[1]")
  pl_read = tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[1]")
  pl_avail = pl_write - pl_read
  
  eps_write = tlm("CHASQUI_II DYNAMICPARS PKTWRITEPTR[3]")
  eps_read = tlm("CHASQUI_II DYNAMICPARS PKTREADPTR[3]")
  eps_avail = eps_write - eps_read
  
  puts "\nDATOS DISPONIBLES:"
  puts "  Beacons:  #{beacon_avail} paquetes"
  puts "  Payload:  #{pl_avail} paquetes"
  puts "  EPS:      #{eps_avail} paquetes"
  puts "  TOTAL:    #{beacon_avail + pl_avail + eps_avail} paquetes"
  
  if (beacon_avail + pl_avail + eps_avail) == 0
    puts "\n✓ No hay datos para descargar"
    return 0
  end
  
  # Descargar beacons
  if beacon_avail > 0
    puts "\n[STEP 2/4] Descargando BEACONS (#{beacon_avail} paquetes)..."
    
    chunks = (beacon_avail / 30.0).ceil
    
    chunks.times do |i|
      chunk_start = beacon_read + (i * 30)
      chunk_size = [30, beacon_avail - (i * 30)].min
      
      puts "  Bloque #{i+1}/#{chunks}: #{chunk_size} paquetes"
      
      cmd("CHASQUI_II PLAYBACK with PARTITION Beacon, READPOINTER #{chunk_start}, NPACKETS #{chunk_size}")
      
      # Esperar recepción
      received = 0
      chunk_size.times do
        begin
          wait_packet("CHASQUI_II", "BEACON", 1, 5)
          received += 1
          print "\r    Recibidos: #{received}/#{chunk_size}"
          STDOUT.flush
        rescue Timeout::Error
          print "\r    Timeout..."
          STDOUT.flush
        end
      end
      
      puts ""
      total_downloaded += received
    puts "✓ EPS descargado"
  else
    puts "\n[STEP 4/4] Saltando EPS (#{eps_avail} paquetes - demasiados)"
  end
  
  # Resumen
  puts "\n" + "="*70
  puts "✓ DESCARGA MASIVA COMPLETADA"
  puts "="*70
  puts "Total descargado: #{total_downloaded} paquetes"
  puts "="*70
  
  return total_downloaded
end

# Ejecución desde Script Runner
if __FILE__ == $0
  mass_data_download()
end