# ============================================================================
# SCRIPT 9: PROGRAMADOR DE PASES
# ============================================================================
# Archivo: procedures/operations/pass_scheduler.rb

load_utility 'ground_station_library'
require 'json'

class PassScheduler
  
  def initialize
    @schedule_file = File.join(Cosmos::USERPATH, 'outputs', 'pass_schedule.json')
    @scheduled_passes = load_schedule()
  end
  
  def load_schedule
    if File.exist?(@schedule_file)
      JSON.parse(File.read(@schedule_file), symbolize_names: true)
    else
      []
    end
  rescue
    []
  end
  
  def save_schedule
    File.open(@schedule_file, 'w') do |f|
      f.puts JSON.pretty_generate(@scheduled_passes)
    end
  end
  
  def add_pass(aos_time, duration, max_elevation, auto_commands: true, auto_download: true)
    pass_id = "PASS_#{aos_time.strftime('%Y%m%d_%H%M%S')}"
    
    pass_entry = {
      id: pass_id,
      aos: aos_time.to_i,
      duration: duration,
      max_elevation: max_elevation,
      auto_commands: auto_commands,
      auto_download: auto_download,
      status: 'scheduled',
      added_at: Time.now.to_i
    }
    
    @scheduled_passes << pass_entry
    save_schedule()
    
    puts "✓ Pase programado: #{pass_id}"
    puts "  AOS:      #{aos_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "  Duración: #{duration} min"
    puts "  Max El:   #{max_elevation}°"
    
    return pass_id
  end
  
  def list_passes
    if @scheduled_passes.empty?
      puts "No hay pases programados"
      return
    end
    
    puts "\n" + "="*70
    puts "PASES PROGRAMADOS"
    puts "="*70
    
    @scheduled_passes.each_with_index do |pass_entry, i|
      aos = Time.at(pass_entry[:aos])
      status_symbol = case pass_entry[:status]
                      when 'scheduled' then '⏰'
                      when 'completed' then '✓'
                      when 'failed' then '✗'
                      else '?'
                      end
      
      puts "\n#{i+1}. #{status_symbol} #{pass_entry[:id]}"
      puts "   AOS:      #{aos.strftime('%Y-%m-%d %H:%M:%S')}"
      puts "   Duración: #{pass_entry[:duration]} min"
      puts "   Max El:   #{pass_entry[:max_elevation]}°"
      puts "   Estado:   #{pass_entry[:status]}"
    end
    
    puts "="*70
  end
  
  def get_next_pass
    now = Time.now.to_i
    
    upcoming = @scheduled_passes.select do |p|
      p[:status] == 'scheduled' && p[:aos] > now
    end
    
    return nil if upcoming.empty?
    
    upcoming.min_by { |p| p[:aos] }
  end
  
  def execute_next_pass
    next_pass = get_next_pass()
    
    unless next_pass
      puts "No hay pases programados"
      return false
    end
    
    aos_time = Time.at(next_pass[:aos])
    
    puts "\n" + "="*70
    puts "EJECUTANDO PASE PROGRAMADO"
    puts "="*70
    puts "ID:       #{next_pass[:id]}"
    puts "AOS:      #{aos_time.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "Duración: #{next_pass[:duration]} min"
    puts "="*70
    
    # Marcar como en ejecución
    next_pass[:status] = 'executing'
    save_schedule()
    
    # Ejecutar pase
    begin
      success = automated_full_pass({
        start_time: aos_time,
        duration: next_pass[:duration],
        max_elevation: next_pass[:max_elevation],
        auto_commands: next_pass[:auto_commands],
        auto_download: next_pass[:auto_download]
      })
      
      # Actualizar estado
      next_pass[:status] = success ? 'completed' : 'failed'
      next_pass[:executed_at] = Time.now.to_i
      save_schedule()
      
      return success
      
    rescue => e
      puts "\n✗ ERROR: #{e.message}"
      next_pass[:status] = 'failed'
      next_pass[:error] = e.message
      save_schedule()
      return false
    end
  end
  
  def monitor_schedule
    puts "="*70
    puts "MONITOR DE PROGRAMACIÓN DE PASES"
    puts "="*70
    puts "Presione Ctrl+C para detener\n"
    
    loop do
      next_pass = get_next_pass()
      
      if next_pass
        aos_time = Time.at(next_pass[:aos])
        time_to_aos = aos_time - Time.now
        
        if time_to_aos > 0
          mins = (time_to_aos / 60).to_i
          secs = (time_to_aos % 60).to_i
          
          print "\r[#{Time.now.strftime('%H:%M:%S')}] Siguiente pase en: #{mins}:#{secs.to_s.rjust(2,'0')} | #{aos_time.strftime('%H:%M:%S')}"
          STDOUT.flush
          
          # Si falta menos de 2 minutos, iniciar pre-pase
          if time_to_aos < 120 && next_pass[:status] == 'scheduled'
            puts "\n\n🚀 Iniciando pase automático..."
            execute_next_pass()
            puts "\n✓ Pase completado. Esperando siguiente...\n"
          end
          
        end
      else
        print "\r[#{Time.now.strftime('%H:%M:%S')}] No hay pases programados"
        STDOUT.flush
      end
      
      wait(1)
    end
  end
  
end

# Ejecución desde Script Runner
if __FILE__ == $0
  scheduler = PassScheduler.new
  
  puts "PROGRAMADOR DE PASES"
  puts "1. Agregar pase"
  puts "2. Listar pases"
  puts "3. Ejecutar siguiente"
  puts "4. Monitor continuo"
  
  option = ask("Seleccione opción:").to_i
  
  case option
  when 1
    aos_str = ask("AOS (YYYY-MM-DD HH:MM:SS):")
    duration = ask("Duración (min):").to_i
    max_el = ask("Elevación máxima:").to_i
    
    aos_time = Time.parse(aos_str)
    scheduler.add_pass(aos_time, duration, max_el)
    
  when 2
    scheduler.list_passes()
    
  when 3
    scheduler.execute_next_pass()
    
  when 4
    scheduler.monitor_schedule()
  end
end