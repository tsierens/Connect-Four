from flask import Flask, render_template, request
from flask_socketio import SocketIO, emit
from random import random
from time import sleep
from threading import Thread, Event
import sys
sys.path.append('..')
import c4_ab as c4
c4.init_wrapper()



app = Flask(__name__)

app.config['DEBUG'] = True


thread = Thread()
thread_stop_event = Event()

available_threads = [Thread() for i in range(5)]

book = {}
filename = '../c4books/book6x7strong.txt'
for line in open(filename,'r'):
    key,result = line.split()
    key = long(key)
    result = int(result)
    book[key] = result
    




app = Flask(__name__)

def get_board_array(board):
    board_array = [[0 for i in xrange(board.columns)] for j in xrange(board.rows)]
    
    for i in xrange(board.rows):
        for j in xrange(board.columns):
            #reading bits from bitboards
            if (board.boards[0] >> i + j * (1 + board.rows)) & 1:
                board_array[i][j] = 1
            elif (board.boards[1] >> i + j * (1 + board.rows)) & 1:
                board_array[i][j] = -1
            else:
                board_array[i][j] = 0
    return board_array
    

def emit_results(d):
    socketio.emit('update', d , namespace='/c4')

def solve(board,moves,identity):
    print 'solving'
    global book
    n_moves = len(board.get_log())
    #board_string = print_board(board)
    board_array = get_board_array(board)
    player = board.get_player()
    legal = board.p_get_legal()
    solved = set()  
    results = [' = ' if move in legal else 'xxx' for move in range(7)]
    d = {'board': board_array,
         'move':-1,
         'depth': 0,
         'results':'|' + '|'.join(results) + '|' , 
         'player':player,
         'finished':0,
         'moves' : moves,
         'id': identity}
    
    for depth in range(board.rows * board.columns+1 - n_moves):
        print 'depth',depth
        print 'results', results
        d['depth'] = depth
        for move in legal:
            d['move'] = move
            if move in solved:
                continue
            board.p_update(move)
            if board.is_over():
                print 'OVER!!!'
                if board.ilog == board.rows*board.columns:
                    result = 0
                else:
                    result = 1
                emit_results(d)
                solved.add(move) 
                    
            else:
                result = int(c4.ab_wrapper(board,depth,book=book,ply = 8))
                result = (43 - abs(result) - n_moves) * (-1 if result > 0 else +1 if result < 0 else 0)
                if result:
                    solved.add(move)
                    emit_results(d)
                            
            board.p_erase()
            results[move] = '{:<+3d}'.format(result) if result != 0 else ' = ' 
            d['results'] = '|' + '|'.join(results) + '|'
        emit_results(d)
    d['finished'] = 1
    emit_results(d)
    global available_threads
    available_threads.append(Thread())
    socketio.emit('disconnect')


def print_board(board):
    big = ''
    for i in xrange(6):
        s = '| '
        for j in xrange(7):
            #s += ' '
            if (board.get_boards()[0] >> i + j * (1 + 6)) & 1:
                s += 'x'
            elif (board.get_boards()[1] >> i + j * (1 + 6)) & 1:
                s += 'o'
            else:
                s += '_'
            s += ' | '
        big = s + '<br/>' + big
    return big

@app.route("/")
def main():
    moves = request.args.get('moves')
    try:
        moves = map(int,list(moves))
        assert(all([move in range(7) for move in moves]))
    except:
        return "Invalid entry"
    board = c4.Board()
    for move in moves:
        board.p_update(move)
      
    return print_board(board)

@app.route("/json")
def json():
    moves = request.args.get('moves')
    board = c4.Board()
    try:
        moves = map(int,list(moves))
        assert(all([move in range(7) for move in moves]))
    except:
        return "Invalid entry"
    board = c4.Board()
    for move in moves:
        board.p_update(move)
    return jsonify(moves = moves , board = print_board(board))

@app.route("/testsocket")
def testsocket():    
    moves = request.args.get('moves')
    print moves
    return render_template('c4.html' ,moves=moves)
    
socketio = SocketIO(app)

clients = []


@socketio.on('evaluate', namespace='/c4')
def evaluate(data):
    #socketio.emit('update', {'board': 'Thinking'})
    global available_threads
    moves = data['moves']
    moves_string = moves
    identity = data['id']
    clients.append(identity)
    print 'Client connected'
    print moves
    board = c4.Board()
    try:
        moves = map(int,list(moves))
        assert(all([move in range(7) for move in moves]))
    except:
        return "Invalid entry"
    board = c4.Board()
    for move in moves:
        board.p_update(move)
    board.print_board()

    print 'Starting Thread'
    if len(available_threads)>0:
        thread = available_threads.pop()
        thread = Thread(target = solve , args = (board,moves_string,identity))
        thread.start()
    else:
        socketio.emit('update', {'board': "No workers availalbe"})
    
    print moves
    print 'workers available', len(available_threads)
    
@socketio.on('disconnect',namespace='/c4')
def disconnect():
    print "Disconnected"
    
#app.run(threaded = True)
            

