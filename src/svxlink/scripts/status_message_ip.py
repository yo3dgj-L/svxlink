import argparse
import re

def update_config_file(filename, message_server_ip, message_server_port):
    # Patterns to search and replace
    patterns = {
        'MESSAGE_SERVER_IP': message_server_ip,
        'MESSAGE_SERVER_PORT': message_server_port
    }

    with open(filename, 'r') as file:
        lines = file.readlines()

    updated_lines = []
    for line in lines:
        stripped_line = line.strip()
        updated = False
        for key, new_value in patterns.items():
            if re.match(rf'#?{key}=.*', stripped_line):
                updated_lines.append(f'{key}={new_value}\n')
                updated = True
                break
        if not updated:
            updated_lines.append(line)

    with open(filename, 'w') as file:
        file.writelines(updated_lines)

    print(f'Updated {filename} successfully.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Update MESSAGE_SERVER_* config lines in a file.')

    parser.add_argument('--file', required=True, help='Path to the configuration file.')
    parser.add_argument('--message-server-ip', required=True, help='New message server IP.')
    parser.add_argument('--message-server-port', required=True, help='New message server port.')

    args = parser.parse_args()

    update_config_file(
        filename=args.file,
        message_server_ip=args.message_server_ip,
        message_server_port=args.message_server_port
    )
