import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { HeliosModule } from './modules/helios/helios.module';
import { BridgeModule } from './modules/bridge/bridge.module';
import { SecondaryModule } from './modules/secondary/secondary.module';
import { APP_FILTER } from '@nestjs/core';
import { HttpExceptionFilter } from './filters/http-exception.filter';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    TypeOrmModule.forRoot({
      type: process.env.NODE_ENV === 'production' ? 'postgresql' : 'sqlite',
      database: process.env.NODE_ENV === 'production'
        ? process.env.DATABASE_URL
        : process.env.DB_PATH || 'data/lxon.db',
      entities: [__dirname + '/**/*.entity{.ts,.js}'],
      synchronize: false,
      logging: process.env.NODE_ENV !== 'production',
    }),
    HeliosModule,
    BridgeModule,
    SecondaryModule,
  ],
  providers: [
    {
      provide: APP_FILTER,
      useClass: HttpExceptionFilter,
    },
  ],
})
export class AppModule {}
