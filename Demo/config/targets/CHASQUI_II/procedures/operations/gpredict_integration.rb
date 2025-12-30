# ============================================================================
# SCRIPT 8: INTEGRACIÓN CON GPREDICT
# ============================================================================
# Archivo: procedures/operations/gpredict_integration.rb

load_utility 'ground_station_library'
require 'socket'
require 'json'

class GpredictInterface
  
  def initialize(host: 'localhost', port: 4532)
    @host = host
    @port = port
    @socket = nil
    @connected = false
  end
  
  def connect
    begin
      @socket = TCPSocket.new(@host, @port)
      @connected = true
      puts "✓ Conectado a Gpredict en #{@host}:#{@port}"
      return true
    rescue => e
      puts "✗ Error conectando a Gpredict: #{e.message}"
      @connected = false
      return false
    end
  end
  
  def disconnect
    @socket.close if @socket
    @connected = false
    puts "✓ Desconectado de Gpredict"
  end
  
  def get_satellite_position
    return nil unless @connected
    
    begin
      @socket.puts("GET_POS")
      response = @socket.gets
      
      # Formato respuesta: "AZ:123.45 EL:45.67"
      if response =~ /AZ:([\d.]+)\s+EL:([\d.]+)/
        azimuth = $1.to_f
        elevation = $2.to_f
        
        return {
          azimuth: azimuth,
          elevation: elevation,
          timestamp: Time.now
        }
      end
      
      return nil
    rescue => e
      puts "Error obteniendo posición: #{e.message}"
      return nil
    end
  end
  
  def get_next_pass
    return nil unless @connected
    
    begin
      @socket.puts("GET_NEXT_PASS")
      response = @socket.gets
      
      # Parsear respuesta de Gpredict
      # Formato: "AOS:timestamp LOS:timestamp MAX_EL:degrees"
      if response =~ /AOS:(\d+)\s+LOS:(\d+)\s+MAX_EL:([\d.]+)/
        aos_time = Time.at($1.to_i)
        los_time = Time.at($2.to_i)
        max_elevation = $3.to_f
        
        return {
          aos: aos_time,
          los: los_time,
          max_elevation: max_elevation,
          duration: ((los_time - aos_time) / 60.0).round(1)
        }
      end
      
      return nil
    rescue => e
      puts "Error obteniendo siguiente pase: #{e.message}"
      return nil
    end
  end
  
end

def track_with_gpredict(duration_min: 10)
  puts "="*70
  puts "SEGUIMIENTO CON GPREDICT"
  puts "="*70
  
  # Conectar a Gpredict
  gpredict = GpredictInterface.new
  
  unless gpredict.connect()
    puts "\n✗ No se pudo conectar a Gpredict"
    puts "Asegúrese de que Gpredict esté ejecutándose con el servidor habilitado"
    return false
  end
  
  # Conectar a rotctld
  begin
    rotor = TCPSocket.new('localhost', 4533)
    puts "✓ Conectado a rotctld"
  rescue
    puts "✗ No se pudo conectar a rotctld"
    gpredict.disconnect()
    return false
  end
  
  # Seguimiento
  puts "\n[TRACKING] Iniciando seguimiento por #{duration_min} minutos..."
  
  start_time = Time.now
  end_time = start_time + (duration_min * 60)
  
  update_count = 0
  
  while Time.now < end_time
    # Obtener posición del satélite desde Gpredict
    position = gpredict.get_satellite_position()
    
    if position
      az = position[:azimuth].round(1)
      el = position[:elevation].round(1)
      
      # Enviar comando al rotor
      rotor.puts("P #{az} #{el}")
      response = rotor.gets
      
      update_count += 1
      
      # Mostrar cada 10 actualizaciones
      if update_count % 10 == 0
        puts "[#{Time.now.strftime('%H:%M:%S')}] Az: #{az}° El: #{el}° (Update ##{update_count})"
      end
      
      # Verificar si el satélite está sobre el horizonte
      if el < 0
        puts "\n[TRACKING] Satélite bajo el horizonte (El: #{el}°)"
        break
      end
      
    else
      puts "⚠ No se pudo obtener posición"
    end
    
    wait(5)  # Actualizar cada 5 segundos
  end
  
  # Cerrar conexiones
  rotor.close
  gpredict.disconnect()
  
  puts "\n✓ Seguimiento completado (#{update_count} actualizaciones)"
  
  return true
end

# Ejecución desde Script Runner
if __FILE__ == $0
  duration = ask("Duración del seguimiento (minutos):").to_i
  track_with_gpredict(duration_min: duration)
end
